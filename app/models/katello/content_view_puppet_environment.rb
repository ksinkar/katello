module Katello
  class ContentViewPuppetEnvironment < Katello::Model
    self.include_root_in_json = false

    include ForemanTasks::Concerns::ActionSubject
    include Glue::Pulp::Repo if SETTINGS[:katello][:use_pulp]
    include Glue if SETTINGS[:katello][:use_pulp]

    belongs_to :environment, :class_name => "Katello::KTEnvironment",
                             :inverse_of => :content_view_puppet_environments
    belongs_to :content_view_version, :class_name => "Katello::ContentViewVersion",
                                      :inverse_of => :content_view_puppet_environments

    has_one :content_view, :through => :content_view_version, :class_name => "Katello::ContentView"

    belongs_to :puppet_environment, :class_name => "Environment",
                                    :inverse_of => :content_view_puppet_environment, :dependent => :destroy

    has_many :content_view_puppet_environment_puppet_modules,
             :class_name => "Katello::ContentViewPuppetEnvironmentPuppetModule",
             :dependent => :destroy
    has_many :puppet_modules,
             :through => :content_view_puppet_environment_puppet_modules

    validates_lengths_from_database
    validates :pulp_id, :presence => true, :uniqueness => true
    validates_with Validators::KatelloNameFormatValidator, :attributes => :name
    validates :puppet_environment, :presence => true, :if => :environment

    before_validation :set_pulp_id

    scope :non_archived, -> { where('environment_id is not NULL') }
    scope :archived, -> { where('environment_id is NULL') }

    def content_type
      Repository::PUPPET_TYPE
    end

    def unprotected
      false
    end

    def node_syncable?
      environment
    end

    def organization
      if self.environment
        self.environment.organization
      else
        self.content_view.organization
      end
    end

    def content_view
      self.content_view_version.content_view
    end

    def self.in_content_view(view_id)
      joins(:content_view_version).where(
          "#{Katello::ContentViewVersion.table_name}.content_view_id" => view_id)
    end

    def self.in_environment(env_id)
      where(environment_id: env_id)
    end

    def archive?
      self.environment.nil?
    end

    def generate_puppet_path(capsule)
      # rubocop:disable Style/EmptyElse
      if self.environment
        File.join(capsule.puppet_path, generate_puppet_env_name, 'modules')
      else
        nil #don't generate archived content view puppet environments
      end
    end

    def generate_puppet_env_name
      if self.environment
        Environment.construct_name(self.organization,
                                   self.environment,
                                   self.content_view)
      end
    end

    def set_pulp_id
      if self.environment
        label = "#{self.content_view.label}-#{self.environment.label}-puppet-#{SecureRandom.uuid}"
      else
        version = self.content_view_version.version.gsub('.', '_')
        label = "#{self.content_view.label}-v#{version}-puppet-#{SecureRandom.uuid}"
      end
      self.pulp_id ||= "#{self.organization.id}-#{label}"
    end

    def index_content(puppet_module_uuids)
      associated_ids = PuppetModule.with_uuid(puppet_module_uuids).pluck(:id)
      self.puppet_modules = PuppetModule.where(:id => associated_ids)
      self.save!
    end

    def self.import_all
      self.all.find_each do |cvpe|
        cvpe.index_content(Katello::Pulp::PuppetModule.ids_for_repository(cvpe.pulp_id))
      end
    end
  end
end
