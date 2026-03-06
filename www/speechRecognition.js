cordova.define("cordova-plugin-speechrecognition.SpeechRecognition", function(require, exports, module) {
  module.exports = {
    isRecognitionAvailable: function(successCallback, errorCallback) {
      cordova.exec(successCallback, errorCallback, 'SpeechRecognition', 'isRecognitionAvailable', []);
    },
    startListening: function(successCallback, errorCallback, options) {
      options = options || {};
      cordova.exec(successCallback, errorCallback, 'SpeechRecognition', 'startListening', [
        options.language || 'en-US',
        options.matches || 5,
        options.prompt || '',
        options.showPartial || false,
        options.showPopup || false,
        options.safetyTimeout || 0
      ]);
    },
    stopListening: function(successCallback, errorCallback) {
      cordova.exec(successCallback, errorCallback, 'SpeechRecognition', 'stopListening', []);
    },
    getSupportedLanguages: function(successCallback, errorCallback) {
      cordova.exec(successCallback, errorCallback, 'SpeechRecognition', 'getSupportedLanguages', []);
    },
    hasPermission: function(successCallback, errorCallback) {
      cordova.exec(successCallback, errorCallback, 'SpeechRecognition', 'hasPermission', []);
    },
    requestPermission: function(successCallback, errorCallback) {
      cordova.exec(successCallback, errorCallback, 'SpeechRecognition', 'requestPermission', []);
    }
  };
});
