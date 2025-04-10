## Usage
1. Import the necessary packages:

```dart
  notification_service:
    git:
      url: https://source.intalio.com/etgs-qatar/shared_group/flutter_packages/notification_service_flutter.git
      ref: main
```
2. Permission:

```dart
add permission in ios Podfile
    target.build_configurations.each do |config|
        #  Preprocessor definitions can be found at: https://github.com/Baseflow/flutter-permission-handler/blob/master/permission_handler_apple/ios/Classes/PermissionHandlerEnums.h
            config.build_settings['GCC_PREPROCESSOR_DEFINITIONS'] ||= [
            '$(inherited)',
            ## dart: PermissionGroup.notification
            'PERMISSION_NOTIFICATIONS=1',
        ]
    end
```
3. Initialization:

```dart
  await NotificationService.init(
    options: DefaultFirebaseOptions.currentPlatform,
    onClickAction: (String? payload) async {},
  );
```
4. Functions:
```dart
    NotificationService.getFCMToken();
    NotificationService.subscribeToTopics();
    NotificationService.showNotification();
    NotificationService.onNotificationClick();
```