# coding: utf-8

module ThinReports
  module Core::Shape
    
    # @private
    class List::Manager
      # @return [ThinReports::Core::Shape::List::Configuration]
      attr_reader :config
      
      # @return [ThinReports::Core::Shape:::List::Page]
      attr_reader :current_page
      
      # @return [ThinReports::Core::Shape::List::PageState]
      attr_reader :current_page_state

      # @return [Integer]
      attr_accessor :page_count
      
      # @param [ThinReports::Core::Shape::List::Page] page
      def initialize(page)
        switch_current!(page)

        @config     = init_config
        @finalized  = false
        @page_count = 0
      end
      
      # @param [ThinReports::Core::Shape::List::Page] page
      # @return [ThinReports::Core::Shape::List::Manager]
      def switch_current!(page)
        @current_page       = page
        @current_page_state = page.internal
        self
      end
      
      # @yield [new_list]
      # @yieldparam [ThinReports::Core::Shape::List::Page] new_list
      def change_new_page(&block)
        finalize_page
        new_page = report.internal.copy_page
        
        if block_given?
          block.call(new_page.list(current_page.id))
        end
      end
      
      # @see List::Page#header
      def header(values = {}, &block)
        unless format.has_header?
          raise ThinReports::Errors::DisabledListSection.new('header')
        end        
        current_page_state.header ||= init_section(:header)
        build_section(current_page_state.header, values, &block)
      end
      
      # @param (see #build_section)
      # @return [Boolean]
      def insert_new_detail(values = {}, &block)
        return false if current_page_state.finalized?
        
        successful = true
        
        if overflow_with?(:detail)
          if auto_page_break?
            change_new_page do |new_list|
              new_list.manager.insert_new_row(:detail, values, &block)
            end
          else
            finalize
            successful = false
          end
        else
          insert_new_row(:detail, values, &block)
        end
        successful
      end
      
      # @see #build_section
      def insert_new_row(section_name, values = {}, &block)
        row = build_section(init_section(section_name), values, &block)
        row.internal.move_top_to(current_page_state.height)
        
        current_page_state.rows << row
        current_page_state.height += row.height
        row
      end
      
      # @param [ThinReports::Core::Shape::List::SectionInterface] section
      # @param values (see ThinReports::Core::Shape::Manager::Target#values)
      # @yield [section,]
      # @yieldparam [ThinReports::Core::Shape::List::SectionInterface] section
      # @return [ThinReports::Core::Shape::List::SectionInterface]
      def build_section(section, values = {}, &block)
        section.values(values)
        block_exec_on(section, &block)
      end
      
      # @param [Symbol] section_name
      # @return [ThinReports::Core::Shape::List::SectionInterface]
      def init_section(section_name)
        List::SectionInterface.new(current_page,
                                   format.sections[section_name],
                                   section_name)
      end      
      
      # @param [Symbol] section_name
      # @return [Boolean]
      def overflow_with?(section_name = :detail)
        max_height = page_max_height
        
        if section_name == :footer && format.has_page_footer?
          max_height += format.section_height(:page_footer)
        end
        
        height = format.section_height(section_name)
        (current_page_state.height + height) > max_height
      end
      
      # @return [Numeric]
      def page_max_height
        unless @page_max_height
          h  = format.height
          h -= format.section_height(:page_footer)
          h -= format.section_height(:footer) unless auto_page_break?
          @page_max_height = h
        end
        @page_max_height
      end
      
      # @return [ThinReports::Core::Shape::List::Store]
      def store
        config.store
      end
      
      # @return [ThinReports::Core::Shape::List::Events]
      def events
        config.events
      end
      
      # @return [Boolean]
      def auto_page_break?
        format.auto_page_break?
      end

      # @param [Hash] options
      # @option [Boolean] :ignore_page_footer (false)
      #   When the switch of the page is generated by #finalize, it is used. 
      # @private
      def finalize_page(options = {})
        return if current_page_state.finalized?
        
        if format.has_header?
          current_page_state.header ||= init_section(:header)
        end
        
        if !options[:ignore_page_footer] && format.has_page_footer?
          footer = insert_new_row(:page_footer)
          # Dispatch page-footer insert event.
          events.
            dispatch(List::Events::SectionEvent.new(:page_footer_insert,
                                                    footer, store))
        end
        current_page_state.finalized!
        
        # Dispatch page finalize event.
        events.
          dispatch(List::Events::PageEvent.new(:page_finalize,
                                               current_page, 
                                               current_page_state.parent))
        @page_count += 1
        current_page_state.no = @page_count
      end
      
      # @private
      def finalize
        return if finalized?
        
        finalize_page
        
        if format.has_footer?
          footer = nil
          
          if auto_page_break? && overflow_with?(:footer)
            change_new_page do |new_list|
              footer = new_list.manager.insert_new_row(:footer)
              new_list.manager.finalize_page(:ignore_page_footer => true)
            end
          else
            footer = insert_new_row(:footer)
          end
          # Dispatch footer insert event.
          events.dispatch(List::Events::SectionEvent.new(:footer_insert,
                                                         footer, store))
        end
        @finalized = true
      end
      
      # @return [Boolean]
      # @private
      def finalized?
        @finalized
      end      
      
    private
      
      # @return [ThinReports::Report::Base]
      def report
        current_page_state.parent.report
      end
      
      # @return [ThinReports::Layout::Base]
      def layout
        current_page_state.parent.layout
      end
      
      # @return [ThinReports::Core::Shape::List::Format]
      def format
        current_page_state.format
      end
      
      # @return [ThinReports::Core::Shape::List::Configuration]
      def init_config
        layout.config.activate(current_page.id) || List::Configuration.new
      end
    end
    
  end
end