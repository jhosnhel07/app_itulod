class AppStrings {
  AppStrings._();

  static const String appName = 'iTULOD';
  static const String appTagline = 'Intelligent Transport and Unified Logistics On-Demand Delivery';
  static const String appRegion = 'Ilocos Transport, Delivery & Logistics';

  // Auth Strings — match iTULOD web mobile copy
  static const String welcomeBack = 'Welcome Back';
  static const String loginSubtitle = 'Log in to continue using iTULOD.';
  static const String emailOrUsername = 'Email or Username';
  static const String emailPlaceholder = 'you@email.com';
  static const String password = 'Password';
  static const String passwordPlaceholder = 'Enter your password';
  static const String confirmPassword = 'Confirm Password';
  static const String rememberMe = 'Remember me';
  static const String forgotPassword = 'Forgot password?';
  static const String loginButton = 'Log In';
  static const String orContinueWith = 'or continue with';
  static const String dontHaveAccount = "Don't have an account?";
  static const String createOne = 'Create one';
  static const String createAccount = 'Create one';
  static const String selectRoleTitle = 'Who are you?';
  static const String selectRoleSubtitle =
      "Choose how you'll use iTULOD. You can always add more roles later.";
  static const String customerRoleTitle = 'Customer';
  static const String customerRoleDesc = 'Book rides, order food, send parcels';
  static const String riderRoleTitle = 'Rider';
  static const String riderRoleDesc = 'Earn by delivering and accepting rides';
  static const String alreadyHaveAccount = 'Already have an account?';
  static const String signIn = 'Login';
  static const String continueLabel = 'Continue';
  static const String personalInfoTitle = 'Personal Information';
  static const String personalInfoCustomerSub =
      'Tell us a bit about yourself to create your account.';
  static const String personalInfoRiderSub =
      'Provide your personal info to start your rider application.';
  static const String vehicleTitle = 'Your Vehicle';
  static const String vehicleSub =
      "Select the type of vehicle you'll use for deliveries and rides.";
  static const String documentsTitle = 'Upload Documents';
  static const String documentsSub =
      'Upload each required document separately. Choose the correct paper, permit, or license for every slot below.';
  static const String reviewTitle = 'Review Your Application';
  static const String reviewSub =
      'Please confirm all details below before submitting your rider application.';
  static const String termsPrefix = 'I agree to the';
  static const String termsOfService = 'Terms of Service';
  static const String privacyPolicy = 'Privacy Policy';
  static const String termsSuffix = 'of iTULOD.';
  static const String customerSuccessTitle = 'Account Created!';
  static const String customerSuccessMessage =
      'Welcome to iTULOD! Your customer account is ready. Start booking rides, ordering food, or sending parcels right away.';
  static const String loginNow = 'Login Now';
  static const String riderSuccessTitle = 'Registration Submitted!';
  static const String riderSuccessMessage =
      'Your rider application has been submitted successfully. Our admin team will review your documents and approve your account.';
  static const String pendingApproval = 'Pending Approval';
  static const String goToLogin = 'Go to Login';
  static const String riderNotifyNote =
      "You'll receive an SMS & email notification once approved.";

  // Rider application
  static const String riderAppTitle = 'Rider Onboarding';
  static const String vehicleDetails = 'Vehicle & License Details';
  static const String licensePhoto = "Driver's License Photo";
  static const String orcrPhoto = 'OR/CR (Vehicle Registration) Photo';
  static const String pendingReviewTitle = 'Application Under Review';
  static const String pendingReviewDesc = 'Your rider application has been submitted and is currently under administrative review. We will notify you once approved.';
  static const String rejectedTitle = 'Application Needs Attention';

  // Booking date/time & expiration
  static const String pastDateTimeError =
      'Please select a valid future date and time.';
  static const String bookingExpiredMessage =
      'This booking has expired because the scheduled date and time has already passed.';
  static const String gracePeriodNote =
      'You have a 15-minute grace period after your scheduled booking time.';
  static const String pendingGracePeriodNote =
      "This request expires automatically if no rider accepts it within 15 minutes.";
}
