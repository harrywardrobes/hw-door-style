require 'tmpdir'

module HarryWardrobes
  module DoorStyle
    # The workshop pack's PDFs straight to the office printer (Settings > Labels > PDF printer,
    # default "BROTHER - Harry Wardrobes") with no print dialog. Labels never go here - they
    # go to the Zebra (Zpl).
    #
    #   SumatraPDF (free, sumatrapdfreader.org) does the printing: Windows has no reliable
    #   built-in way to print a PDF without opening it. Found in Program Files / AppData, or
    #   the path in Settings. Without it, Windows' "PrintTo" for the default PDF app is tried
    #   (works with Adobe Reader; not with Edge).
    module PdfPrint
      DEFAULT = 'BROTHER - Harry Wardrobes'.freeze

      def self.printer
        p = Settings.get['pdf_printer'].to_s.strip
        p.empty? ? DEFAULT : p
      end

      SIDES = { 'simplex' => 'Single sided', 'duplexlong' => 'Double sided (long edge)', 'duplexshort' => 'Double sided (short edge)' }.freeze

      # Single sided unless Settings > Labels > PDF printer says otherwise.
      def self.sides
        v = Settings.get['pdf_sides'].to_s
        SIDES.key?(v) ? v : 'simplex'
      end

      def self.sumatra
        s = Settings.get['sumatra_path'].to_s.strip
        return s if !s.empty? && File.exist?(s)
        dirs = [ENV['ProgramFiles'], ENV['ProgramFiles(x86)'], ENV['LOCALAPPDATA'], ENV['LOCALAPPDATA'] && File.join(ENV['LOCALAPPDATA'], 'Programs')]
        dirs.compact.uniq.map { |d| File.join(d, 'SumatraPDF', 'SumatraPDF.exe') }.find { |f| File.exist?(f) }
      end

      # The printers Windows has: [[name, share name]], or nil if they can't be read.
      def self.printers
        require 'win32ole'
        WIN32OLE.connect('winmgmts://').ExecQuery('SELECT Name, ShareName FROM Win32_Printer').each.map { |p| [p.Name.to_s, p.ShareName.to_s] }
      rescue StandardError, LoadError => e
        Log.info("printer list: #{e.message}")
        nil
      end

      # The configured printer as Windows names it (case / spacing forgiven); raises with the
      # printers there are when it isn't found.
      def self.resolve
        want = printer
        list = printers
        return want if list.nil?
        # the setting can be the printer's Windows name, its network share name ("BROTHER - Harry
        # Wardrobes") or \\computer\share; spacing / capitals forgiven. Never a guess.
        norm = ->(n) { n.to_s.downcase.gsub(/\s+/, ' ').strip }
        w = norm.call(want.to_s.sub(/\A\\\\[^\\]+\\/, ''))
        hit = list.find { |name, share| norm.call(name) == w || (!share.empty? && norm.call(share) == w) || norm.call(name).end_with?("\\#{w}") }
        return hit[0] if hit
        raise "There's no printer called or shared as \"#{want}\" on this computer. Printers: #{list.map { |n, sh| sh.empty? ? n : "#{n} (shared as #{sh})" }.join(', ')}. Set the name in Settings > Labels > PDF printer."
      end

      # Prints each PDF (in order) on the printer. Raises with what to do when it can't.
      def self.print(files)
        files = Array(files).select { |f| f && File.exist?(f) && f =~ /\.pdf\z/i }
        return 0 if files.empty?
        exe = sumatra
        raise 'SumatraPDF isn\'t installed (free, sumatrapdfreader.org) - it prints the PDFs without a dialog. Or set its path in Settings > Labels.' unless exe
        name = resolve
        files.each do |f|
          args = [exe.tr('/', '\\'), '-print-to', name, '-print-settings', "fit,paper=A4,#{sides}", '-silent', f.tr('/', '\\')]
          ok = system(*args)
          Log.info("pdf print #{File.basename(f)} on #{name}: #{ok.inspect} (#{$?.inspect})")
          next if ok
          raise "Couldn't print #{File.basename(f)} on \"#{name}\" (SumatraPDF exit #{$?&.exitstatus.inspect}). Check the printer is on and the name in Settings > Labels matches Windows."
        end
        files.size
      end

      # Settings > Labels > PDF printer > Test print: one A4 page.
      def self.test_page
        path = File.join(Dir.tmpdir, 'hw_pdf_printer_test.pdf')
        pg = Pdf::Page.new
        pg.text(Pdf::MARGIN, Pdf::PAGE_H - 80, 'HW Door Style - PDF printer test', font: 'F2', size: 18)
        pg.text(Pdf::MARGIN, Pdf::PAGE_H - 104, "Printer: #{printer}   |   #{Time.now.strftime('%d/%m/%Y %H:%M')}", size: 10)
        File.binwrite(path, Pdf.document([pg.to_s]))
        print([path])
      end
    end
  end
end
