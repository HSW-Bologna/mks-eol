# mks_eol

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## TODO

 - Add `delayedOperator` target that allows the operator to skip only after a certain time
 - The current target should only contain one current level; when started it tries to reach it with a certain step every certain period of time
 - The `ViewUpdater` should be a repository, not a `Bloc` or `Cubit`. 
    The updating part should be handled by each page's specific `Bloc`, just managing messages and reactivity.
