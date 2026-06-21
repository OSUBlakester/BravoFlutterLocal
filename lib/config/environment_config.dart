enum Environment {
  dev,
  test,
  prod,
}

class EnvironmentConfig {
  static const Environment _currentEnvironment = Environment.prod; // Change this to switch environments
  
  // Firebase Configuration
  static const String _devProjectId = 'bravo-dev-465400';
  static const String _testProjectId = 'bravo-test-465400';
  static const String _prodProjectId = 'bravo-prod-465323';
  
  // API Base URLs
  static const String _devApiUrl = 'https://dev.talkwithbravo.com';
  static const String _testApiUrl = 'https://test.talkwithbravo.com';
  static const String _prodApiUrl = 'https://app.talkwithbravo.com';
  
  // Firebase Web Configuration
  static const Map<Environment, Map<String, String>> _firebaseWebConfig = {
    Environment.dev: {
      'apiKey': 'AIzaSyAS7GVK_A34iE56IJoSAN2KbG2w9rxlWTM',
      'authDomain': 'bravo-dev-465400.firebaseapp.com',
      'projectId': 'bravo-dev-465400',
      'storageBucket': 'bravo-dev-465400.firebasestorage.app',
      'messagingSenderId': '894197055102',
      'appId': '1:894197055102:web:d71bf54b2166ca8aba222f',
      'measurementId': 'G-NQKM7HSYHZ',
    },
    Environment.test: {
      'apiKey': 'AIzaSyDLE187Rp4Y-78dEqSOwMOESMT-fRnTRbI',
      'authDomain': 'bravo-test-465400.firebaseapp.com',
      'projectId': 'bravo-test-465400',
      'storageBucket': 'bravo-test-465400.firebasestorage.app',
      'messagingSenderId': '22852552488',
      'appId': '1:22852552488:web:e77b29ff19b3b6999ff21d',
    },
    Environment.prod: {
      'apiKey': 'AIzaSyBHm_5sPgZmDezwHzg6E7_DyAgKcb6jf0g',
      'authDomain': 'bravo-prod-465323.firebaseapp.com',
      'projectId': 'bravo-prod-465323',
      'storageBucket': 'bravo-prod-465323.firebasestorage.app',
      'messagingSenderId': '222892987413',
      'appId': '1:222892987413:web:b68db62cbdef3089a22a1c',
      'measurementId': 'G-0LL27W14WL',
    },
  };
  
  // Firebase iOS Configuration
  static const Map<Environment, Map<String, String>> _firebaseIosConfig = {
    Environment.dev: {
      'apiKey': 'AIzaSyAS7GVK_A34iE56IJoSAN2KbG2w9rxlWTM',
      'appId': '1:894197055102:ios:3a98ab000ecec15aba222f',
      'messagingSenderId': '894197055102',
      'projectId': 'bravo-dev-465400',
      'storageBucket': 'bravo-dev-465400.firebasestorage.app',
    },
    Environment.test: {
      'apiKey': 'AIzaSyCxn6tC4LMOa-bqi2e80_N8sVt29OIBvxM',
      'appId': '1:22852552488:ios:70b18674e62d66fe9ff21d',
      'messagingSenderId': '22852552488',
      'projectId': 'bravo-test-465400',
      'storageBucket': 'bravo-test-465400.firebasestorage.app',
    },
    Environment.prod: {
      'apiKey': 'AIzaSyBHm_5sPgZmDezwHzg6E7_DyAgKcb6jf0g',
      'appId': '1:222892987413:ios:9fef78a73ef90517a22a1c',
      'messagingSenderId': '222892987413',
      'projectId': 'bravo-prod-465323',
      'storageBucket': 'bravo-prod-465323.firebasestorage.app',
    },
  };
  
  // Getters for current environment
  static Environment get currentEnvironment => _currentEnvironment;
  
  static String get apiBaseUrl {
    switch (_currentEnvironment) {
      case Environment.dev:
        return _devApiUrl;
      case Environment.test:
        return _testApiUrl;
      case Environment.prod:
        return _prodApiUrl;
    }
  }
  
  static String get projectId {
    switch (_currentEnvironment) {
      case Environment.dev:
        return _devProjectId;
      case Environment.test:
        return _testProjectId;
      case Environment.prod:
        return _prodProjectId;
    }
  }
  
  static Map<String, String> get firebaseWebConfig {
    return _firebaseWebConfig[_currentEnvironment]!;
  }
  
  static Map<String, String> get firebaseIosConfig {
    return _firebaseIosConfig[_currentEnvironment]!;
  }
  
  static String get environmentName {
    switch (_currentEnvironment) {
      case Environment.dev:
        return 'Development';
      case Environment.test:
        return 'Test';
      case Environment.prod:
        return 'Production';
    }
  }
  
  static bool get isProduction => _currentEnvironment == Environment.prod;
  static bool get isDevelopment => _currentEnvironment == Environment.dev;
  static bool get isTest => _currentEnvironment == Environment.test;
}
