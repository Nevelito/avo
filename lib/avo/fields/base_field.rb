module Avo
  module Fields
    class BaseField
      extend ActiveSupport::DescendantsTracker

      prepend Avo::Concerns::HasItemType
      prepend Avo::Concerns::IsResourceItem
      include Avo::Concerns::IsVisible
      include Avo::Concerns::VisibleInDifferentViews
      include Avo::Concerns::HasHelpers
      include Avo::Fields::Concerns::HasFieldName
      include Avo::Fields::Concerns::HasDefault
      include Avo::Fields::Concerns::HasHTMLAttributes
      include Avo::Fields::Concerns::HandlesFieldArgs
      include Avo::Fields::Concerns::IsReadonly
      include Avo::Fields::Concerns::IsDisabled
      include Avo::Fields::Concerns::IsRequired
      include Avo::Fields::Concerns::UseViewComponents

      include ActionView::Helpers::UrlHelper

      delegate :app, to: ::Avo::Current
      delegate :view_context, to: :app
      delegate :context, to: :app
      delegate :simple_format, :content_tag, to: :view_context
      delegate :main_app, to: :view_context
      delegate :avo, to: :view_context
      delegate :t, to: ::I18n

      attr_reader :id
      attr_reader :block
      attr_reader :required
      attr_reader :readonly
      attr_reader :sortable
      attr_reader :summarizable
      attr_reader :nullable
      attr_reader :null_values
      attr_reader :format_using
      attr_reader :format_display_using
      attr_reader :format_index_using
      attr_reader :format_show_using
      attr_reader :format_edit_using
      attr_reader :format_new_using
      attr_reader :format_form_using
      attr_reader :autocomplete
      attr_reader :help
      attr_reader :default
      attr_reader :stacked
      attr_reader :for_presentation_only
      attr_reader :for_attribute

      # Private options
      attr_reader :computable # if allowed to be computable
      attr_reader :computed # if block is present
      attr_reader :computed_value # the value after computation
      attr_reader :copyable # if allowed to be copyable

      # Hydrated payload
      attr_accessor :record
      attr_accessor :action
      attr_accessor :user
      attr_accessor :panel_name

      class_attribute :field_name_attribute

      def initialize(id, **args, &block)
        @id = id
        @name = args[:name]
        @translation_key = args[:translation_key]
        @block = block
        @required = args.dig(:required) # Value if :required present on args, nil otherwise
        @readonly = args[:readonly] || false
        @disabled = args[:disabled] || false
        @sortable = args[:sortable] || false
        @summarizable = args[:summarizable] || false
        @nullable = args[:nullable] || false
        @null_values = args[:null_values] || [nil, ""]
        @format_using = args[:format_using]
        @format_display_using = args[:format_display_using] || args[:decorate]

        unless Rails.env.production?
          if args[:decorate].present?
            puts "[Avo DEPRECATION WARNING]: The `decorate` field configuration option is nolonger supported and will be removed in future versions. Please discontinue its use and solely utilize `format_display_using` instead."
          end
        end

        @format_index_using = args[:format_index_using]
        @format_show_using = args[:format_show_using]
        @format_edit_using = args[:format_edit_using]
        @format_new_using = args[:format_new_using]
        @format_form_using = args[:format_form_using]
        @update_using = args[:update_using]
        @decorate = args[:decorate]
        @placeholder = args[:placeholder]
        @autocomplete = args[:autocomplete]
        @help = args[:help]
        @default = args[:default]
        @visible = args[:visible]
        @html = args[:html]
        @view = Avo::ViewInquirer.new(args[:view])
        @value = args[:value]
        @stacked = args[:stacked]
        @for_presentation_only = args[:for_presentation_only] || false
        @resource = args[:resource]
        @action = args[:action]
        @components = args[:components] || {}
        @for_attribute = args[:for_attribute]
        @meta = args[:meta]
        @copyable = args[:copyable] || false

        @args = args

        @computable = true
        @computed = block.present?
        @computed_value = nil

        post_initialize if respond_to?(:post_initialize)
      end

      def translation_key
        @translation_key || "avo.field_translations.#{@id}"
      end

      def translated_name(default:)
        t(translation_key, count: 1, default: default).humanize
      end

      def translated_plural_name(default:)
        t(translation_key, count: 2, default: default).humanize
      end

      # Getting the name of the resource (user/users, post/posts)
      # We'll first check to see if the user passed a name
      # Secondly we'll try to find a translation key
      # We'll fallback to humanizing the id
      def name
        if custom_name?
          Avo::ExecutionContext.new(target: @name).handle
        elsif translation_key
          translated_name default: default_name
        else
          default_name
        end
      end

      def plural_name
        default = name.pluralize

        if translation_key
          translated_plural_name default: default
        else
          default
        end
      end

      def table_header_label
        @table_header_label ||= name
      end

      def custom_name?
        !@name.nil?
      end

      def default_name
        @id.to_s.humanize(keep_id_suffix: true)
      end

      def placeholder
        Avo::ExecutionContext.new(target: @placeholder || name, record: record, resource: @resource, view: @view).handle
      end

      def attribute_id = (@attribure_id ||= @for_attribute || @id)

      def value(property = nil)
        return @value if @value.present?

        property ||= attribute_id

        # Get record value
        final_value = @record.send(property) if is_model?(@record) && @record.respond_to?(property)

        # On new views and actions modals we need to prefill the fields with the default value if value is nil
        if final_value.nil? && should_fill_with_default_value? && @default.present?
          final_value = computed_default_value
        end

        # Run computable callback block if present
        if computable && @block.present?
          final_value = execute_context(@block)
        end

        # Format value based on available formatter
        final_value = format_value(final_value)

        if @decorate.present? && @view.display?
          final_value = execute_context(@decorate, value: final_value)
        end

        final_value
      end

      def execute_context(target, **extra_args)
        Avo::ExecutionContext.new(
          target:,
          record: @record,
          resource: @resource,
          view: @view,
          field: self,
          include: self.class.included_modules,
          **extra_args
        ).handle
      end

      # Fills the record with the received value on create and update actions.
      def fill_field(record, key, value, params)
        key = @for_attribute.to_s if @for_attribute.present?
        return record unless has_attribute?(record, key)

        record.public_send(:"#{key}=", apply_update_using(record, key, value, resource))

        record
      end

      def apply_update_using(record, key, value, resource)
        return value if @update_using.nil?

        Avo::ExecutionContext.new(
          target: @update_using,
          record:,
          key:,
          value:,
          resource:,
          field: self,
          include: self.class.included_modules
        ).handle
      end

      def has_attribute?(record, attribute)
        record.methods.include? attribute.to_sym
      end

      # Try to see if the field has a different database ID than it's name
      def database_id
        foreign_key
      rescue
        id
      end

      def has_own_panel?
        false
      end

      def resolve_attribute(value)
        value
      end

      def to_permitted_param
        id.to_sym
      end

      def record_errors
        record.present? ? record.errors : {}
      end

      def type
        @type ||= self.class.name.demodulize.to_s.underscore.gsub("_field", "")
      end

      def custom?
        !method(:initialize).source_location.first.include?("lib/avo/field")
      rescue
        true
      end

      def visible_in_reflection?
        true
      end

      def hidden_in_reflection?
        !visible_in_reflection?
      end

      def options_for_filter
        options
      end

      def updatable
        !is_disabled? && visible?
      end

      # Used by Avo to fill the record with the default value on :new and :edit views
      def assign_value(record:, value:)
        id = (type == "belongs_to") ? foreign_key : database_id

        if record.send(id).nil?
          record.send(:"#{id}=", value)
        end
      end

      def form_field_label
        id
      end

      def meta
        Avo::ExecutionContext.new(target: @meta, record: record, resource: @resource, view: @view).handle
      end

      private

      def model_or_class(model)
        model.instance_of?(String) ? "class" : "model"
      end

      def is_model?(model)
        model_or_class(model) == "model"
      end

      def should_fill_with_default_value?
        on_create? || in_action?
      end

      def on_create?
        @view.in?(%w[new create])
      end

      def in_action?
        @action.present?
      end

      def get_resource_by_model_class(model_class)
        resource = Avo.resource_manager.get_resource_by_model_class(model_class)

        resource || (raise Avo::MissingResourceError.new(model_class, self))
      end

      def format_value(value)
        final_value = value

        formatters_by_view = {
          index: [:format_index_using, :format_display_using, :format_using],
          show: [:format_show_using, :format_display_using, :format_using],
          edit: [:format_edit_using, :format_form_using, :format_using],
          new: [:format_new_using, :format_form_using, :format_using]
        }

        current_view = @view.to_sym
        applicable_formatters = formatters_by_view[current_view]

        applicable_formatters&.each do |formatter|
          formatter_value = instance_variable_get(:"@#{formatter}")
          if formatter_value.present?
            return execute_context(formatter_value, value: final_value)
          end
        end

        final_value
      end
    end
  end
end
