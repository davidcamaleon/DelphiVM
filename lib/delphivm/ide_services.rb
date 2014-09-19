require 'delphivm/tool'
require 'delphivm/win_services'

class Delphivm
	IDEInfos = Delphivm.configuration.known_ides || {}

 	class IDEServices
		attr :idever
		attr :workdir
		attr :build_tool

		def self.idelist(kind = :installed)
			ide_filter_valid?(kind) ? send("ides_in_#{kind}") : []
		end

		def self.ide_filter_valid?(kind)
			%W(config installed prj).include?(kind.to_s)
		end

		def self.default_ide
		 	(ides_in_prj.last || ides_in_installed.last).to_s
		end

		def self.ides_in_config
		 	IDEInfos.to_h.keys.sort
		end

		def self.ides_in_installed
			ides_filter(ides_in_config, :installed)
		end

		def self.ides_in_prj
			ides_filter(ides_in_config, :prj)
		end

		def self.ides_filter(ides, kind)
			ide_filter_valid?(kind) ? ides.select {|ide| send("ide_in_#{kind}?", ide)} : []
		end

		def self.ide_in_config?(ide)
			ides_in_config.include?(ide)
		end

		def self.ide_in_installed?(ide)
			(Win32::Registry::HKEY_CURRENT_USER.open(IDEInfos[ide][:regkey]) {|reg| reg} rescue false)
		end

		def self.ide_in_prj?(ide)
		 	!ROOT.glob("{src,samples,test}/#{ide.to_s}*/").empty?
		end

		def self.platforms_in_prj(ide)
			result = []
			Pathname.glob(ROOT + "{src,samples,test}/**/*.dproj") do |f|
				doc = Nokogiri::XML(File.open(f))
				result = result | doc.css("Platforms Platform").select{|node| node.content=='True'}.map{|node| node.attr(:value)}
			end
			result
		end

		def self.configs_in_prj(ide)
			result = []
			Pathname.glob(ROOT + "{src,samples,test}/**/*.dproj") do |f|
				doc = Nokogiri::XML(File.open(f))
				result = result | doc.css("BuildConfiguration[@Include != 'Base']").map{|node| node.attr('Include')}
			end
			result
		end

		def self.ide_folder(ide)
			"#{ide}-#{IDEInfos[ide][:name]}"
		end

		def self.use(ide_tag, activate=true)#experimental, aun parece no funcionar
			paths_to_remove = []
			ides_in_installed.each {|tag| paths_to_remove += ide_paths(tag)}
		 	paths_to_remove.map!{|p| p.win }
			path = ENV['PATH'].split(';')
			new_path = ide_paths(ide_tag.upcase) + path - paths_to_remove
	  	path = new_path.join(';')
			WinServices.winpath = path if activate
			path
		end

		def initialize(idever, workdir=ROOT)
			@idever = idever.to_s.upcase
			@workdir = workdir
			@reg = Win32::Registry::HKEY_CURRENT_USER
			@build_tool = supports_msbuild? ? MSBuild.new(self) : IDETool.new(self)
		end

		def [](key)
		  @reg.open(IDEInfos[idever][:regkey]) {|r| r[key] }
		end

		def set_env
		 	p ENV["PATH"] = vendor_bin_paths.join(';') + ';' + IDEServices.use(idever,false)

		 	ENV["BDSPROJECTGROUPDIR"] = workdir.win
		 	ENV["IDEVERSION"] = idever.to_s
		end

		def prj_slug
		 	workdir.basename.to_s.upcase
		end

		def prj_regkey(prjslug=nil)
			prjslug ||= prj_slug
			"DelphiVM\\#{prjslug}"
		end

		def ide_regkey
			IDEInfos[idever][:regkey]
		end

		def pkg_regkey
			regkey = Pathname(ide_regkey)
			"HKCU\\#{regkey.parent.parent}\\#{prj_regkey}\\#{regkey.basename}\\Known Packages"
		end

  	def ide_root_path
    		Pathname(self['RootDir'])
  	end

		def vendor_bin_paths
		    Pathname.glob(PATH_TO_VENDOR_IMPORTS + idever + '**' + 'bin').map{|p| p.win}
		end

		def supports_msbuild?
			ide_number = idever[1..-1].to_i
			ide_number > 140
		end

		def group_file_ext
			supports_msbuild? ? 'groupproj' : 'bdsgroup'
		end

		def proj_file_ext
			'dproj'
		end

		def get_main_group_file
			Pathname.glob(workdir + "src/#{idever}**/#{prj_slug}App.#{group_file_ext}").first ||
			Pathname.glob(workdir + "src/#{idever}**/*.#{group_file_ext}").first ||
			Pathname.glob(workdir + "src/*.#{group_file_ext}").first ||
			Pathname.glob(workdir + "*.#{group_file_ext}").first
		end

		def start(main_group_file=nil)
			set_env
			main_group_file ||= get_main_group_file
			#bds_args = IDETool.new(self).args(file: main_group_file.win).cmdln_args
			bds_args = IDETool.new(self).cmdln_args
			Process.detach(spawn("#{self['App']}", *bds_args))
			say "[#{idever}] ", :green
			say "started bds #{bds_args.join(" ")}"
		end

		def call_build_tool(target, config)
		 	set_env
			Pathname.glob(workdir + "{src,samples,test}/#{idever}**/*.#{group_file_ext}") do |f|
				f_to_show = f.relative_path_from(workdir)
				build_tool.args(config: config, target: target, file: f.win)
				say "[#{idever}] ", :green
				say "#{target.upcase}: #{f_to_show}"
				say("[#{build_tool.title}] ", :green)
				say(build_tool.cmdln_args.join(" "))
				say
			 	WinServices.winshell(out_filter: ->(line){line =~/\b(warning|hint|error)\b/i}) do |i|
			 	#WinServices.winshell do |i|
					build_tool.call(i)
				end
			end
	  	end
  	private

		def self.say(*args)
			Delphivm.shell.say(*args)
		end

		def say(*args)
			self.class.say(*args)
		end

		def self.ide_paths(idetag=IDEServices.default_ide)
			public_path = Pathname(ENV["PUBLIC"]) + 'Documents'
			ide = IDEServices.new(idetag)
			base_path = ide.ide_root_path
			brand_path = Pathname(base_path.each_filename.to_a[1..-1].join('/'))
			bin_paths = [base_path + 'bin', base_path + 'bin64'].map{|p| Pathname(p.win)}
			bpl_paths = [public_path + brand_path + 'Bpl', public_path + brand_path + 'Bpl' + 'Win64'].map{|p| Pathname(p.win)}
			return bin_paths + bpl_paths
  	end
	end
end