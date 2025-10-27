run:
	flutter run --dart-define-from-file=dart_defines.json

run-ios:
	flutter run -d ios --dart-define-from-file=dart_defines.json

run-android:
	flutter run -d android --dart-define-from-file=dart_defines.json

build-apk:
	flutter build apk --dart-define-from-file=dart_defines.json

build-ios:
	flutter build ios --no-codesign --dart-define-from-file=dart_defines.json

