<script>
import { mapGetters } from 'vuex';
import { useVuelidate } from '@vuelidate/core';
import { useAlert } from 'dashboard/composables';
import { required } from '@vuelidate/validators';
import router from '../../../../index';
import { isPhoneE164OrEmpty, isNumber } from 'shared/helpers/Validators';
import globalConfigMixin from 'shared/mixins/globalConfigMixin';
import LoadingState from 'dashboard/components/widgets/LoadingState.vue';
import { loadFBsdk, initFB } from 'shared/helpers/facebookInitializer';
import AccountAPI from '../../../../../api/account'

import { loadScript } from 'dashboard/helper/DOMHelpers';
import * as Sentry from '@sentry/vue';




export default {
  setup() {
    return { v$: useVuelidate() };
  },
  components: {
    LoadingState,
  },
  mixins: [globalConfigMixin],
  data() {
    return {
      inboxName: '',
      phoneNumber: '',
      apiKey: '',
      phoneNumberId: '',
      businessAccountId: '',
      hasLoginStarted: false,
      emptyStateMessage: this.$t('INBOX_MGMT.DETAILS.LOADING_FB'),
      isFbConnected: false,
      selectedPhoneNumber: {},
      phone_numbers: [],
    };
  },
  computed: {
    ...mapGetters({ 
      uiFlags: 'inboxes/getUIFlags',
      globalConfig: 'globalConfig/get',
    }),
  },
  created() {
    
    // loadFBsdk();
  },
  mounted() {
    window.fbAsyncInit = initFB;
    // initFB();
  },
  validations: {
    inboxName: { required },
    phoneNumber: { required, isPhoneE164OrEmpty },
    apiKey: { required },
    phoneNumberId: { required, isNumber },
    businessAccountId: { required, isNumber },
  },
  methods: {
    async createChannel() {
      this.v$.$touch();
      if (this.v$.$invalid) {
        return;
      }

      try {
        const whatsappChannel = await this.$store.dispatch(
          'inboxes/createChannel',
          {
            name: this.inboxName,
            channel: {
              type: 'whatsapp',
              phone_number: this.phoneNumber,
              provider: 'whatsapp_embedded',
              provider_config: {
                api_key: this.apiKey,
                phone_number_id: this.phoneNumberId,
                business_account_id: this.businessAccountId,
              },
            },
          }
        );

        router.replace({
          name: 'settings_inboxes_add_agents',
          params: {
            page: 'new',
            inbox_id: whatsappChannel.id,
          },
        });
      } catch (error) {
        useAlert(
          error.message || this.$t('INBOX_MGMT.ADD.WHATSAPP.API.ERROR_MESSAGE')
        );
      }
    },
    async startLogin() {
      this.hasLoginStarted = true;

      try {
        // this will load the SDK in a promise, and resolve it when the sdk is loaded
        // in case the SDK is already present, it will resolve immediately
        await this.loadFBsdk();
        this.initFB(); // run init anyway, `initFB` won't wait for `fbAsyncInit` otherwise.
        this.tryFBlogin(); // make an attempt to login
      } catch (error) {
        if (error.name === 'ScriptLoaderError') {
          // if the error was related to script loading, we show a toast
          useAlert(this.$t('INBOX_MGMT.DETAILS.ERROR_FB_LOADING'));
        } else {
          // if the error was anything else, we capture it and show a toast
          Sentry.captureException(error);
          console.log(error)
          useAlert(this.$t('INBOX_MGMT.DETAILS.ERROR_FB_AUTH'));
        }
      }
    },
    showLoader() {
      return !this.user_access_token || this.isCreating;
    },
    initFB() {
      FB.init({
        appId: window.chatwootConfig.fbAppId,
        xfbml: true,
        version: window.chatwootConfig.fbApiVersion,
        autoLogAppEvents : true,
      });
      window.fbSDKLoaded = true;
      FB.AppEvents.logPageView();
    },
    
    async loadFBsdk() {
      return loadScript('https://connect.facebook.net/en_US/sdk.js', {
        id: 'facebook-jssdk',
      });
    },
    tryFBlogin() {
      FB.login(
        (response) => {
          if (response.status === 'connected') {
            // Use an async IIFE inside the synchronous callback
            (async () => {
              try {
                const WABAIDresponse = await AccountAPI.getWABAID(response.authResponse.code);
                this.businessAccountId = WABAIDresponse.data.waba_id;
                this.phone_numbers = WABAIDresponse.data.phone_numbers;
                this.isFbConnected = true;
                this.apiKey = WABAIDresponse.data.api_key;
              } catch (error) {
                console.error('Error fetching WABA ID:', error);
                useAlert(this.$t('INBOX_MGMT.DETAILS.ERROR_FB_AUTH'));
              }
            })(); // End of async IIFE
          } else if (response.status === 'not_authorized') {
            this.emptyStateMessage = this.$t('INBOX_MGMT.DETAILS.ERROR_FB_AUTH');
          } else {
            this.emptyStateMessage = this.$t('INBOX_MGMT.DETAILS.ERROR_FB_AUTH');
          }
        },
        {
          config_id: window.chatwootConfig.fbConfigID,
          response_type: 'code',
          override_default_response_type: true,
          scope: 'business_management, whatsapp_business_management, whatsapp_business_messaging, public_profile',
          extras: {
            feature: 'whatsapp_embedded_signup',
            version: 2,
            setup: {
              // Prefilled data can go here
            },
          },
        }
      );
    },
    formatPhoneNumber(phoneNumber) {
      return phoneNumber.replace(/[- ]/g, '');
    },
  },
  watch: {
    
    selectedPhoneNumber(newVal) {
      if (newVal) {
        this.phoneNumberId = newVal.id;
        this.phoneNumber = this.formatPhoneNumber(newVal.display_phone_number);
      }
    }
  },
};
</script>

<template>
  <form class="flex flex-wrap mx-0" @submit.prevent="createChannel()">
    <div 
      v-if="apiKey !== ''"
      class="w-[65%] flex-shrink-0 flex-grow-0 max-w-[65%]"
    >
      <label :class="{ error: v$.inboxName.$error }">
        {{ $t('INBOX_MGMT.ADD.WHATSAPP.INBOX_NAME.LABEL') }}
        <input
          v-model="inboxName"
          type="text"
          :placeholder="$t('INBOX_MGMT.ADD.WHATSAPP.INBOX_NAME.PLACEHOLDER')"
          @blur="v$.inboxName.$touch"
        />
        <span v-if="v$.inboxName.$error" class="message">
          {{ $t('INBOX_MGMT.ADD.WHATSAPP.INBOX_NAME.ERROR') }}
        </span>
      </label>
    </div>

    <div 
      v-if="apiKey !== ''" 
      class="w-[65%] flex-shrink-0 flex-grow-0 max-w-[65%]"
    >
      <label :class="{ error: v$.phoneNumber.$error }">
        {{ $t('INBOX_MGMT.ADD.WHATSAPP.PHONE_NUMBER.LABEL') }}
        <select
          v-model.trim="selectedPhoneNumber"
          type="text"
          :placeholder="$t('INBOX_MGMT.ADD.WHATSAPP.PHONE_NUMBER.PLACEHOLDER')"
          @blur="$v.phoneNumber.$touch"
        >
          <option v-for="phone in phone_numbers" :key="phone.id" :value="phone">
            {{ phone.display_phone_number }}
          </option>
        </select>
        <span v-if="v$.phoneNumber.$error" class="message">
          {{ $t('INBOX_MGMT.ADD.WHATSAPP.PHONE_NUMBER.ERROR') }}
        </span>
      </label>
    </div>

    <div 
      v-if="apiKey !== ''" 
      class="w-[65%] flex-shrink-0 flex-grow-0 max-w-[65%]"
    >
      <label :class="{ error: v$.phoneNumberId.$error }">
        <span>
          {{ $t('INBOX_MGMT.ADD.WHATSAPP.PHONE_NUMBER_ID.LABEL') }}
        </span>
        <input
          v-model="phoneNumberId"
          type="text"
          :placeholder="
            $t('INBOX_MGMT.ADD.WHATSAPP.PHONE_NUMBER_ID.PLACEHOLDER')
          "
          @blur="v$.phoneNumberId.$touch"
          disabled
        />
        <span v-if="v$.phoneNumberId.$error" class="message">
          {{ $t('INBOX_MGMT.ADD.WHATSAPP.PHONE_NUMBER_ID.ERROR') }}
        </span>
      </label>
    </div>

    <div 
      v-if="apiKey !== ''" 
      class="w-[65%] flex-shrink-0 flex-grow-0 max-w-[65%]"
    >
      <label :class="{ error: v$.businessAccountId.$error }">
        <span>
          {{ $t('INBOX_MGMT.ADD.WHATSAPP.BUSINESS_ACCOUNT_ID.LABEL') }}
        </span>
        <input
          v-model="businessAccountId"
          type="text"
          :placeholder="
            $t('INBOX_MGMT.ADD.WHATSAPP.BUSINESS_ACCOUNT_ID.PLACEHOLDER')
          "
          @blur="v$.businessAccountId.$touch"
          disabled
        />
        <span v-if="v$.businessAccountId.$error" class="message">
          {{ $t('INBOX_MGMT.ADD.WHATSAPP.BUSINESS_ACCOUNT_ID.ERROR') }}
        </span>
      </label>
    </div>
    <div v-if="apiKey === ''" class="w-[65%] flex-shrink-0 flex-grow-0 max-w-[65%]">
      <div
        v-if="!hasLoginStarted"
        class="login-init text-left medium-8 mb-1 columns p-0"
      >
        <a href="#" @click="startLogin()">
          <img
            src="~dashboard/assets/images/channels/facebook_login.png"
            alt="Facebook-logo"
          />
        </a>
      </div>
      <div v-else class="login-init medium-8 columns p-0">
        <LoadingState v-if="showLoader" :message="emptyStateMessage" />
      </div>
    </div>
    <div class="w-full">
      <woot-submit-button
        :loading="uiFlags.isCreating"
        :button-text="$t('INBOX_MGMT.ADD.WHATSAPP.SUBMIT_BUTTON')"
      />
    </div>
  </form>
</template>

<style scoped>
.p-0 {
  padding: 0%;
}
.text-left {
  text-align: left;
}

.mb-1 {
  margin-bottom: 1.6rem;
}
</style>
