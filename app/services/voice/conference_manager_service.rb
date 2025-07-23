module Voice
  class ConferenceManagerService
    pattr_initialize [:conversation!, :event!, :call_sid!, :participant_label]

    def process
      case event
      when 'conference-start'
        handle_conference_start
      when 'conference-end'
        handle_conference_end
      when 'participant-join'
        handle_participant_join
      when 'participant-leave'
        handle_participant_leave
      end

      conversation.save!
    end

    private

    def call_status_manager
      @call_status_manager ||= Voice::CallStatus::Manager.new(
        conversation: conversation,
        call_sid: call_sid,
        provider: :twilio
      )
    end

    def handle_conference_start
      current_status = conversation.additional_attributes['call_status']
      return if %w[in_progress ended].include?(current_status)

      call_status_manager.process_status_update('ringing')
    end

    def handle_conference_end
      current_status = conversation.additional_attributes['call_status']

      if current_status == 'in_progress'
        call_status_manager.process_status_update('ended')
      elsif current_status == 'ringing'
        call_status_manager.process_status_update('no_answer')
      else
        call_status_manager.process_status_update('ended')
      end
    end

    def handle_participant_join
      if agent_participant?
        handle_agent_join
      elsif caller_participant?
        handle_caller_join
      end
    end

    def handle_participant_leave
      if caller_participant? && call_in_progress?
        call_status_manager.process_status_update('ended')
      elsif caller_participant? && ringing_call? && !agent_joined?
        call_status_manager.process_status_update('no_answer')
      end
    end

    def handle_agent_join
      conversation.additional_attributes['agent_joined_at'] = Time.now.to_i

      return unless ringing_call?

      call_status_manager.process_status_update('in_progress')
    end

    def handle_caller_join
      conversation.additional_attributes['caller_joined_at'] = Time.now.to_i

      return unless outbound_call? && ringing_call?

      call_status_manager.process_status_update('in_progress')
    end

    def agent_participant?
      participant_label&.start_with?('agent')
    end

    def caller_participant?
      participant_label&.start_with?('caller')
    end

    def outbound_call?
      conversation.additional_attributes['call_direction'] == 'outbound'
    end

    def ringing_call?
      conversation.additional_attributes['call_status'] == 'ringing'
    end

    def call_in_progress?
      conversation.additional_attributes['call_status'] == 'in_progress'
    end

    def agent_joined?
      conversation.additional_attributes['agent_joined_at'].present?
    end
  end
end
