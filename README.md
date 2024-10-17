# mks_eol

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## TODO

 - ~Aggiungere messaggio in caso di configurazione errata!~
 - ~Recupero della comunicazione~
 - ~Tasto "Interrompi"~
 - ~Enter -> avanti, Esc -> Interrompi~

 - Aggiungere la possibilita' di controllare uno dei valori; vai avanti se va bene
 - 3 valori che devono essere a x uno dall'altro, 1 che deve essere entro un certo range da y (i 4 valori + tensione e potenza (max 15000) vanno salvati)

 - Aggiungere la possibilita' di avanzare automaticamente da uno step "load"
 - Tasto "salta"

 - The `ViewUpdater` should be a repository, not a `Bloc` or `Cubit`. 
    The updating part should be handled by each page's specific `Bloc`, just managing messages and reactivity.
