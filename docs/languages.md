# languages

how to add a language to exteria. there are two ways: a `.strings` file that anyone can load on the phone, and a language built into the app.

## the file

the texts of the app live in `resources/localization/<code>.lproj/Localizable.strings`. the keys are the keys of the english file, `en.lproj`, and a language only translates values.

```
"language.name" = "Deutsch";
"language.english" = "German";
"language.base" = "de";

"welcome.title.1" = "Schnell";
"chat.members.one" = "%ld Teilnehmer";
"chat.members.other" = "%ld Teilnehmer";
```

start from a template: settings, language, then "English template" or "Russian template" shares the bundled file. translate the values, keep the keys. a key you leave out stays english.

## load it on the phone

1. copy the file to the Documents folder of Exteria with file sharing, or send it to the phone any other way that ends in a place the file browser can reach
2. settings, language, "Import a language", choose the file
3. the new row appears in the list; tap it to use it

the code of the language is `x-` and the name of the file, lowercase, with only letters, digits, `-` and `_`, 32 characters at most. `german.strings` becomes `x-german`. a file with the same name replaces the language, and if it is in force the new texts apply at once. "Remove" in the row takes it away; when it was the one in use, the language of the system comes back.

## what a file says about itself

three keys are not texts of the app. all are optional.

- `language.name`: the name in its own language, shown in the list; the name of the file when missing
- `language.english`: the name in english, the line under it; `language.name` when missing
- `language.base`: the real language the file is written in, as a code such as `de`; `en` when missing or not a code the translator knows

the base is what everything but the texts follows: dates and weekday names, the translator target, notifications. it also picks the plural forms, see below. a base the app does not know is not an error, it falls back to `en`.

## placeholders

`%@`, `%d`, `%ld`, `%lld` and the rest must stand in the same order and be the same kind as in the english text. a text where they differ is left out, because a wrong one crashes the screen that shows it. the import tells you how many were left out.

- `%%` is a percent sign and does not count
- `\n` is a line break, keep it where the layout needs it
- numbered placeholders (`%1$@`) are compared by kind and order, the number itself is not checked

## plurals

a word that depends on a count has one key for each form, `<key>.one`, `<key>.few`, `<key>.other`, and the app asks for the form of the count.

- the base `ru`: `one` after a last digit of 1, `few` after 2 to 4, `other` otherwise, and `other` for 11 to 14
- every other base: `one` for exactly 1, `other` for the rest

so a file with another base needs `.one` and `.other` only; a `.few` key in it is never asked for. the english file carries `.few` keys too, so the template has them, and they can be dropped.

## limits

- 2 MiB per file, 20000 keys
- 12 custom languages at most
- a value must not be empty; empty values are dropped
- keys that are not in the english file are dropped

a refused file says why: unreadable (not a valid `.strings` file), too large, a name with no letters or digits, too many languages, or no text of the app in it.

where the file is kept: `Application Support/Exteria/Languages/<code>.lproj/Localizable.strings`, the list of names in the user defaults.

## a language built into the app

for a language that ships in the ipa. this changes code, so it needs a build.

1. make `resources/localization/<code>.lproj/Localizable.strings`, with `<code>` a real language code (`de`, `pl`). the build copies every `lproj` of that folder into the app
2. add the code to the list in `ExteriaInterfaceLanguageCodes` in `app/translate/exteria_language.m`; the language screen lists them in that order
3. add it to `CFBundleLocalizations` in `packaging/Info.plist`
4. if its plural rules are not "one and other", add them to `ExteriaPluralForm` in `app/ui/shared/exteria_plural.m` and write the forms your rules name
5. put `language.name` and `language.english` nowhere: a bundled language is named by the system (`ExteriaNativeLanguageName`), only custom ones carry their own name

the same rules as for a file apply: keys of `en.lproj`, placeholders in the same order. a missing key shows the english text, not the key, but a bundled language should be complete. check that no key is missing:

```bash
cd resources/localization
diff <(grep -o '^"[^"]*"' en.lproj/Localizable.strings | sort) <(grep -o '^"[^"]*"' de.lproj/Localizable.strings | sort)
```

plural keys of other forms show up in that diff, which is right.

`sqmrak.lproj` is made from `ru.lproj` by `tools/make_sqmrak_strings.py`. run the script again after the russian texts change and never edit its output by hand.

## check

1. choose the language in the app and walk the screens that have long words: the tab bar, settings rows, the chat input, alerts
2. a text that is too long for its place is shortened in the translation, not in the layout

nothing in the repository tests the texts. how a script looks in the fonts of an old system has to be seen on a real device.
