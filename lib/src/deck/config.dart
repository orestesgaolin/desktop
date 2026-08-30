/// Presentation-wide metadata used by shared slide chrome.
class DeckConfig {
  const DeckConfig({
    required this.title,
    required this.author,
    required this.date,
    required this.place,
    required this.website,
  });

  final String title;
  final String author;
  final String date;
  final String place;
  final String website;

  String get titleDetails =>
      [author, date, place].where((part) => part.trim().isNotEmpty).join(' · ');

  String get footerText => [
    title,
    author,
    date,
    place,
  ].where((part) => part.trim().isNotEmpty).join(' · ');
}

/// One restrained system family across the deck. Change it here if the
/// presentation later moves to bundled, cross-platform font assets.
const deckFontFamily = 'Avenir Next';

/// Edit presentation metadata here; every numbered slide footer uses it.
const deckConfig = DeckConfig(
  title: 'State of Flutter Desktop',
  author: 'Dominik Roszkowski',
  date: 'MMXXVI',
  place: 'Flutter & Friends',
  website: 'roszkowski.dev',
);
