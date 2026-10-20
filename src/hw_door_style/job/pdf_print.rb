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

      def self.sumatra
        s = Settings.get['sumatra_path'].to_s.strip
        return s if !s.empty? && File.exist?(s)
        dirs = [ENV['ProgramFiles'], ENV['ProgramFiles(x86)'], ENV['LOCALAPPDATA'], ENV['LOCALAPPDATA'] && File.join(ENV['LOCALAPPDATA'], 'Programs')]
        dirs.compact.uniq.map { |d| File.join(d, 'SumatraPDF', 'SumatraPDF.exe') }.find { |f| File.exist?(f) }
      end

      # Prints each PDF (in order) on the printer. Raises with what to do when it can't.
      def self.print(files)
        files = Array(files).select { |f| f && File.exist?(f) && f =~ /\.pdf\z/i }
        return 0 if files.empty?
        exe = sumatra
        files.each do |f|
          ok = if exe
                 system(exe, '-print-to', printer, '-print-settings', 'fit,paper=A4', '-silent', f)
               else
                 q = ->(s) { s.to_s.gsub("'", "''") }
                 system('powershell', '-NoProfile', '-WindowStyle', 'Hidden', '-Command',
                        "Start-Process -FilePath '#{q.call(f)}' -Verb PrintTo -ArgumentList '\"#{q.call(printer)}\"' -WindowStyle Hidden -ErrorAction Stop")
               end
          next if ok
          raise "Couldn't print #{File.basename(f)} on \"#{printer}\". " +
                (exe ? 'Check the printer name in Settings > Labels matches Windows exactly.' : 'Install SumatraPDF (free, sumatrapdfreader.org) so PDFs can print without a dialog, or set its path in Settings > Labels.')
        end
        files.size
      end
    end
  end
end
