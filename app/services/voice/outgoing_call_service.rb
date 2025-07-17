module Voice
  class OutgoingCallService
    pattr_initialize [:account!, :contact!, :user!]

    def process
      find_voice_inbox

      # Create conversation and voice message in a single transaction
      # This ensures the voice call message is created before any auto-assignment activity messages
      ActiveRecord::Base.transaction do
        create_conversation
        initiate_call
        create_voice_call_message
      end

      # Add the activity message separately, after the voice call message
      create_activity_message

      @conversation
    end

    private

    def find_voice_inbox
      @voice_inbox = account.inboxes.find_by(channel_type: 'Channel::Voice')
      raise 'No Voice channel found' if @voice_inbox.blank?
      raise 'Contact has no phone number' if contact.phone_number.blank?
      
    end

    def create_conversation
      # Use the ConversationFinderService to create the conversation
      @conversation = Voice::ConversationFinderService.new(
        account: account,
        phone_number: contact.phone_number,
        is_outbound: true,
        inbox: @voice_inbox,
        call_sid: nil # This will be set after call is initiated
      ).perform

      # Need to reload conversation to get the display_id populated by the database
      @conversation.reload

      # Log the conversation ID and display_id for debugging
      # Conversation created for outgoing call

      # The conference_sid should be set by the ConversationFinderService, but we double-check
      @conference_name = @conversation.additional_attributes['conference_sid']

      # Verify conference name is valid, if not, fix it
      if @conference_name.blank? || !@conference_name.match?(/^conf_account_\d+_conv_\d+$/)
        # Generate proper conference name
        @conference_name = "conf_account_#{account.id}_conv_#{@conversation.display_id}"

        # Store it in the conversation
        @conversation.additional_attributes['conference_sid'] = @conference_name
        @conversation.save!

        # Logging removed
      else
        # Logging removed
      end
    end

    def initiate_call
      # Double-check that we have a valid conference name before calling
      if @conference_name.blank? || !@conference_name.match?(/^conf_account_\d+_conv_\d+$/)
        # Logging removed

        # Re-generate the conference name as a last resort
        @conference_name = "conf_account_#{account.id}_conv_#{@conversation.display_id}"
        # Logging removed

        # Update the conversation with the new conference name
        @conversation.additional_attributes['conference_sid'] = @conference_name
        @conversation.save!
      else
        # Logging removed
      end

      # Log that we're about to initiate the call
        # Logging removed

      # Initiate the call using the channel's implementation
      @call_details = @voice_inbox.channel.initiate_call(
        to: contact.phone_number,
        conference_name: @conference_name,
        agent_id: user.id # Pass the agent ID to track who initiated the call
      )

      # Log the returned call details for debugging
        # Logging removed

      # Update conversation with call details, but don't set status
      # Status will be properly set by CallStatusManager
      updated_attributes = @conversation.additional_attributes.merge({
        'call_sid' => @call_details[:call_sid],
        'requires_agent_join' => true,
        'agent_id' => user.id, # Store the agent ID who initiated the call
        'conference_sid' => @conference_name, # Ensure conference_sid is set correctly
        'conference_name' => @conference_name, # Add an additional field for backwards compatibility
      })

      # Ensure the call is marked as outbound
      updated_attributes['call_direction'] = 'outbound'

      # Save the updated attributes
      @conversation.update!(additional_attributes: updated_attributes)

      # Log the final conversation state
        # Logging removed
    end

    def create_voice_call_message
      # Create a voice call message
      # Initialize CallStatusManager to get normalized status
      status_manager = Voice::CallStatus::Manager.new(
        conversation: @conversation,
        call_sid: @call_details[:call_sid],
        provider: :twilio
      )
      
      # Get UI-friendly status
      ui_status = status_manager.normalized_ui_status('ringing')
      
      message_params = {
        content: 'Voice Call',
        message_type: 'outgoing',
        content_type: 'voice_call',
        content_attributes: {
          data: {
            call_sid: @call_details[:call_sid],
            status: ui_status, # Set the normalized UI status
            conversation_id: @conversation.display_id,
            call_direction: 'outbound',
            conference_sid: @conference_name,
            from_number: @voice_inbox.channel.phone_number,
            to_number: contact.phone_number,
            agent_id: user.id,
            meta: {
              created_at: Time.now.to_i,
              ringing_at: Time.now.to_i
            }
          }
        }
      }

      # Create just the voice call message - this ensures it appears first in the conversation
      @widget_message = Messages::MessageBuilder.new(
        user,
        @conversation,
        message_params
      ).perform

      # Update last activity timestamp
      @conversation.update(last_activity_at: Time.current)
    end

    # Create the activity message in a separate method
    def create_activity_message
      # Initialize the status manager with provider information
      status_manager = Voice::CallStatus::Manager.new(
        conversation: @conversation,
        call_sid: @call_details[:call_sid],
        provider: :twilio # Specify the provider for accurate messaging
      )

      # Process first status update with a custom message instead of default
      # This creates only one activity message
      custom_message = "Outgoing call to #{contact.name || contact.phone_number}"
      status_manager.process_status_update('initiated', nil, true, custom_message)
    end

  end
end
