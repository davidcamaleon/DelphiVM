require 'fiddle'
require 'fiddle/import'

module User32
	extend Fiddle::Importer
	dlload 'user32'
	extern 'long SendMessageTimeout(long, long, long, void*, long, long, void*)'
end

HWND_BROADCAST = 0xffff
WM_SETTINGCHANGE = 0x001A
SMTO_ABORTIFHUNG = 2

class	Delphivm
 	class IDEServices
		attr :idever
		attr :workdir
		GROUP_FILE_EXT = ['groupproj', 'bdsgroup']
		MSBUILD_ARGS = 
		IDEInfos = Delphivm.configuration.known_ides || {}

	def self.idelist(kind = :found)
		ide_filter_valid?(kind) ? send("ides_#{kind}") : []
	end
	
	def self.ide_filter_valid?(kind)
		%W(known found used).include?(kind.to_s)
	end

	def self.default_ide
	 	self.ides_used.last
	end
		
	def self.ides_known
	 	known_ides = IDEInfos.to_h.keys.sort
	end

	def self.ides_found
		ides_filter(ides_known, :found)
	end

	def self.ides_used
		ides_filter(ides_known, :used)
	end

	def self.ides_filter(ides, kind)
		ide_filter_valid?(kind) ? ides.select {|ide| send("ide_#{kind}?", ide)} : []
	end

	def self.ide_known?(ide)
		ides_known.include?(ide)
	end

	def self.ide_found?(ide)
		(Win32::Registry::HKEY_CURRENT_USER.open(IDEInfos[ide][:regkey]) {|reg| reg} rescue false)
	end
	
	def self.ide_used?(ide)
	 	!ROOT.glob("{src,samples,test}/#{ide.to_s}**/*.{#{GROUP_FILE_EXT.join(',')}}").empty?
	end

	def self.use(ide_tag)
	 	bin_paths = ide_paths.map{ |p| p + 'bin' }

	 	paths_to_remove = [""] + bin_paths + bpl_paths + bipl_paths
	 	p paths_to_remove =  paths_to_remove.map{|p| p.upcase}
         
	 	path = Win32::Registry::HKEY_CURRENT_USER.open('Environment'){|r| r['PATH']}
	 	path = path.split(';')
	 	p "============= Entrada"
	 	p path
	 	path.reject! { |p|  paths_to_remove.include?(p.upcase)  }
	 	p "============= Borrado"
	 	p path

	 	new_bin_path = ide_paths(ide_tag.upcase).map{ |p| p + 'bin' }.first
	  	path.unshift new_bin_path

	 	new_bpl_path = ide_paths(ide_tag.upcase).map{ |p| p + 'bpl' }.first
	  	path.unshift new_bpl_path
	 	p "============= Final"
	 	p path

	  	path = path.join(';')
	  	self.winpath = path
	  	return path
	end
		
	def initialize(idever, workdir)
		@idever = idever.upcase
		@workdir = workdir
		@reg = Win32::Registry::HKEY_CURRENT_USER     
	end
	 
	def [](key)
	  @reg.open(IDEInfos[idever][:regkey]) {|r|  r[key] }
	end
	  
	def set_env
	 	ENV["PATH"] = '$(BDSCOMMONDIR)\bpl;' + ENV["PATH"]
	 	ENV["PATH"] = self['RootDir'] + 'bin;' + ENV["PATH"]
	 	ENV["BDSPROJECTGROUPDIR"] = workdir.win
	 	ENV["IDEVERSION"] = idever.to_s
	 	say "set BDSPROJECTGROUPDIR=#{workdir.win}"
	 	say "IDEVERSION=#{idever.to_s}"
	end

	def start
		set_env
		Process.detach(spawn "#{self['App']}", "-rDelphiVM\\#{prj_slug}")
		say "started bds -rDelphiVM\\#{prj_slug}"
	end
	
	def prj_slug
	 	workdir.basename.to_s.upcase
	end
	
	def supports_msbuild?(idever)
		ide_number = idever[1..-1].to_i
		ide_number > 140			
	end
		
	def msbuild(target, config)
	 	set_env
	 	#self.class.winshell(out_filter: ->(line){line =~/\b(warning|error)\b/i}) do |i|
	 	self.class.winshell do |i|
		Pathname.glob(workdir + "{src,samples,test}/#{idever}**/*.{#{GROUP_FILE_EXT.join(',')}}") do |f|
			 f_to_show = f.relative_path_from(workdir)
			 # paths can contains spaces so we need use quotes
			if supports_msbuild?(idever)
				msbuild_prms = config.inject([]) {|prms, item| prms << '/p:' + item.join('=')}.join(' ')
				say "using #{idever}"
				say %Q[msbuild /nologo /consoleloggerparameters:v=quiet /filelogger /flp:v=detailed /t:#{target} #{msbuild_prms} "#{f.win}" ...]
				i.puts %Q["#{self['RootDir'] + 'bin\rsvars.bat'}"]
				i.puts %Q[msbuild /nologo /consoleloggerparameters:v=quiet /filelogger /flp:v=detailed /t:#{target} #{msbuild_prms} "#{f.win}"]
			else						
				say "using #{idever}"
				say "bds -b #{f_to_show.win} ...."
				i.puts %Q[bds -b "#{f.win}"]
			end
		end  
	  end    
	end
	
	def self.winshell(options = {})
		acmd = options[:cmd] || 'cmd /k'
		out_filter = options[:out_filter] || ->(line){true}
		err_filter = options[:err_filter] || ->(line){true}

		Open3.popen3(acmd) do |i, o, e, t|
			err_t = Thread.new(e) do |stm|
				while (line = stm.gets)
					say "STDERR: #{line}" if err_filter.call(line)
				end
			end 

			out_t = Thread.new(o) do |stm|
				while (line = stm.gets)
					say "#{line}" if out_filter.call(line) 
				end
			end

			begin
				yield i if block_given?
				i.close
				err_t.join
				out_t.join
				o.close
				e.close
			rescue Exception => excep
				say excep
			end
			t.value
		end      
	end

  private
	
	def self.say(msg)
		puts msg
	end
		
	def say(msg)
		self.class.say(msg)
	end

	def self.ide_paths(idetag=nil)
		result = []
		IDEInfos.each do |key, info|
			Win32::Registry::HKEY_CURRENT_USER.open(info[:regkey]) { |r| 	
				result << r['RootDir'] if (idetag.nil? || idetag.to_s == key)
			} rescue true
		end
		result
	end
	
	def self.winpath=(path)
		Win32::Registry::HKEY_CURRENT_USER.open('Environment', Win32::Registry::KEY_WRITE) do |r| 
			r['PATH'] = path
		end
		User32.SendMessageTimeout(HWND_BROADCAST, WM_SETTINGCHANGE, 0, 'Environment', SMTO_ABORTIFHUNG, 5000, 0)    
	end
  end
end