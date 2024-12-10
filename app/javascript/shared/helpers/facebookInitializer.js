/* global FB */

export const initFB = () => {
  FB.init({
    appId: window.chatwootConfig.fbAppId,
    xfbml: true,
    version: window.chatwootConfig.fbApiVersion,
    autoLogAppEvents : true,
  });
  window.fbSDKLoaded = true;
  FB.AppEvents.logPageView();
};
export const loadFBsdk = () => {
  ((d, s, id) => {
    let js;
    // eslint-disable-next-line
    const fjs = (js = d.getElementsByTagName(s)[0]);
    if (d.getElementById(id)) {
      return;
    }
    js = d.createElement(s);
    js.id = id;
    js.src = '//connect.facebook.net/en_US/sdk.js';
    fjs.parentNode.insertBefore(js, fjs);
  })(document, 'script', 'facebook-jssdk');
};

export const unloadFacebookSDK = () => {
  // Get the Facebook SDK script element
  var fbSDKScript = document.getElementById('facebook-jssdk');

  // Remove the Facebook SDK script element from the DOM
  if (fbSDKScript) {
    fbSDKScript.parentNode.removeChild(fbSDKScript);
  }
  window.fbSDKLoaded = undefined;
  // Remove the global `FB` object
  delete window.FB;
};
