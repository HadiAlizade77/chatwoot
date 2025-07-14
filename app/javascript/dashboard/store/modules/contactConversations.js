import * as types from '../mutation-types';
import ContactAPI from '../../api/contacts';
import ConversationApi from '../../api/conversations';
import camelcaseKeys from 'camelcase-keys';
import axios from 'axios';

export const createMessagePayload = (payload, message) => {
  const { content, cc_emails, bcc_emails } = message;
  payload.append('message[content]', content);
  if (cc_emails) payload.append('message[cc_emails]', cc_emails);
  if (bcc_emails) payload.append('message[bcc_emails]', bcc_emails);
};

export const createConversationPayload = ({ params, contactId, files }) => {
  const { inboxId, message, sourceId, mailSubject, assigneeId } = params;
  const payload = new FormData();

  if (message) {
    createMessagePayload(payload, message);
  }

  if (files && files.length > 0) {
    files.forEach(file => payload.append('message[attachments][]', file));
  }

  payload.append('inbox_id', inboxId);
  payload.append('contact_id', contactId);
  payload.append('source_id', sourceId);
  payload.append('additional_attributes[mail_subject]', mailSubject);
  payload.append('assignee_id', assigneeId);

  return payload;
};

export const createWhatsAppConversationPayload = ({ params }) => {
  const { inboxId, message, contactId, sourceId, assigneeId } = params;

  const payload = {
    inbox_id: inboxId,
    contact_id: contactId,
    source_id: sourceId,
    message,
    assignee_id: assigneeId,
  };

  return payload;
};

const setNewConversationPayload = ({
  isFromWhatsApp,
  params,
  contactId,
  files,
}) => {
  if (isFromWhatsApp) {
    return createWhatsAppConversationPayload({ params });
  }
  return createConversationPayload({
    params,
    contactId,
    files,
  });
};

const state = {
  records: {},
  uiFlags: {
    isFetching: false,
  },
};

export const getters = {
  getUIFlags($state) {
    return $state.uiFlags;
  },
  getContactConversation: $state => id => {
    return $state.records[Number(id)] || [];
  },
  getAllConversationsByContactId: $state => id => {
    const records = $state.records[Number(id)] || [];
    return camelcaseKeys(records, { deep: true });
  },
};

export const actions = {
  create: async ({ commit }, { params, isFromWhatsApp, isVoiceCall }) => {
    commit(types.default.SET_CONTACT_CONVERSATIONS_UI_FLAG, {
      isCreating: true,
    });
    const { contactId, files } = params;
    try {
      // Create the basic payload
      const payload = setNewConversationPayload({
        isFromWhatsApp,
        params,
        contactId,
        files,
      });

      // If this is a voice call, adjust the endpoint to trigger voice
      let data;

      if (isVoiceCall) {
        const accountId = window.store.getters['accounts/getCurrentAccountId'];

        if (contactId) {
          // Use the regular contacts call endpoint for existing contacts
          const response = await axios.post(
            `/api/v1/accounts/${accountId}/contacts/${contactId}/call`
          );
          data = response.data;
        } else {
          // For direct phone calls without a contact, use a special endpoint
          // Add phoneNumber to the payload for voice call
          payload.phone_number = params.phoneNumber || '';
          const response = await axios.post(
            `/api/v1/accounts/${accountId}/conversations/trigger_voice`,
            payload
          );
          data = response.data;
        }
      } else {
        // Regular conversation creation
        const response = await ConversationApi.create(payload);
        data = response.data;
      }

      if (contactId) {
        commit(types.default.ADD_CONTACT_CONVERSATION, {
          id: contactId,
          data,
        });
      }

      return data;
    } catch (error) {
      throw new Error(error);
    } finally {
      commit(types.default.SET_CONTACT_CONVERSATIONS_UI_FLAG, {
        isCreating: false,
      });
    }
  },
  get: async ({ commit }, contactId) => {
    commit(types.default.SET_CONTACT_CONVERSATIONS_UI_FLAG, {
      isFetching: true,
    });
    try {
      const response = await ContactAPI.getConversations(contactId);
      commit(types.default.SET_CONTACT_CONVERSATIONS, {
        id: contactId,
        data: response.data.payload,
      });
      commit(types.default.SET_CONTACT_CONVERSATIONS_UI_FLAG, {
        isFetching: false,
      });
    } catch (error) {
      commit(types.default.SET_CONTACT_CONVERSATIONS_UI_FLAG, {
        isFetching: false,
      });
    }
  },
};

export const mutations = {
  [types.default.SET_CONTACT_CONVERSATIONS_UI_FLAG]($state, data) {
    $state.uiFlags = {
      ...$state.uiFlags,
      ...data,
    };
  },
  [types.default.SET_CONTACT_CONVERSATIONS]: ($state, { id, data }) => {
    $state.records = {
      ...$state.records,
      [id]: data,
    };
  },
  [types.default.ADD_CONTACT_CONVERSATION]: ($state, { id, data }) => {
    const conversations = $state.records[id] || [];

    const updatedConversations = [...conversations];
    const index = conversations.findIndex(
      conversation => conversation.id === data.id
    );

    if (index !== -1) {
      updatedConversations[index] = { ...conversations[index], ...data };
    } else {
      updatedConversations.push(data);
    }

    $state.records = {
      ...$state.records,
      [id]: updatedConversations,
    };
  },
  [types.default.DELETE_CONTACT_CONVERSATION]: ($state, id) => {
    const { [id]: deletedRecord, ...remainingRecords } = $state.records;
    $state.records = remainingRecords;
  },
};

export default {
  namespaced: true,
  state,
  getters,
  actions,
  mutations,
};
