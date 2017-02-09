require "active_model"
require "reform/form/active_model"
require "uber/delegates"

module Reform
  class Contract::Result::Errors
    extend Forwardable

    # inject methods for rails to make it smell like a hash
    def_delegators :messages, :empty?, :size, :count
  end

  # class Contract::Result
  #   def errors(*args);   filter_for(:errors, *args) end
  #   def messages(*args); filter_for(:messages, *args) end
  # end

  # class Contract::Result::Pointer
  #   def errors(*args); @result.errors.traverse_for(:messages, *args) end
  #   def messages(*args); errors end
  # end

  module Form::ActiveModel
  # AM::Validations for your form.
  # Provides ::validates, ::validate, #validate, and #valid?.
  #
  # Most of this file contains unnecessary wiring to make ActiveModel's error message magic work.
  # Since Rails still thinks it's a good idea to do things like object.class.human_attribute_name,
  # we have some hacks in here to provide that. If it doesn't work for you, don't blame us.
    module Validations
      def self.included(includer)
        includer.instance_eval do
          include Reform::Form::ActiveModel

          class << self
            extend Uber::Delegates
            # # Hooray! Delegate translation back to Reform's Validator class which contains AM::Validations.
            delegates :active_model_really_sucks, :human_attribute_name, :lookup_ancestors, :i18n_scope # Rails 3.1.

            def validation_group_class
              Group
            end

            # this is to allow calls like Form::human_attribute_name (note that this is on the CLASS level) to be resolved.
            # those calls happen when adding errors in a custom validation method, which is defined on the form (as an instance method).
            def active_model_really_sucks
              Class.new(Validator).tap do |v|
                v.model_name = model_name
              end
            end
          end
        end # ::included
      end

      # The concept of "composition" has still not arrived in Rails core and they rely on 400 methods being
      # available in one object. This is why we need to provide parts of the I18N API in the form.
      def read_attribute_for_validation(name)
        send(name)
      end

      class Group
        def initialize(*)
          @validations = Class.new(Reform::Form::ActiveModel::Validations::Validator)
        end

        extend Uber::Delegates
        delegates :@validations, :validates, :validate, :validates_with, :validate_with

        def call(form)
          validator = @validations.new(form)
          validator.valid? # run the validations
          return validator
        end
      end

      # Validator is the validatable object. On the class level, we define validations,
      # on instance, it exposes #valid?.
      require "delegate"
      class Validator < SimpleDelegator
        # current i18n scope: :activemodel.
        include ActiveModel::Validations

        class << self
          def model_name
            @_active_model_sucks ||= ActiveModel::Name.new(Reform::Form, nil, "Reform::Form")
          end

          def model_name=(name)
            @_active_model_sucks = name
          end

          def validates(*args, &block)
            super(*Declarative::DeepDup.(args), &block)
          end

          # Prevent AM:V from mutating the validator class
          def attr_reader(*)
          end

          def attr_writer(*)
          end
        end

        def initialize(form)
          super(form)
          self.class.model_name = form.model_name
        end

        # hints don't exist in AMV so lets just return an empty hash
        def hints
          {}
        end

        # Provide access to the messages hash for new reform errors API
        def messages
          errors.messages
        end

        def failure?
          !success?
        end

        def success?
          messages.size == 0
        end

        # rather than redefining #errors which would break rails form builders, lets just
        # define fetch to delegate to errors.messages
        def fetch(key, &block)
          messages.fetch(key, &block)
        end

        def method_missing(m, *args, &block)
          __getobj__.send(m, *args, &block) # send all methods to the form, even privates.
        end
      end
    end
    # class Errors < ActiveModel::Errors
    #   extend Forwardable
    #
    #   def initialize(errors)
    #     @errors
    #   end
    #
    #   def_delegators :@errors, :success?, :failure?
    # end
  end
end
