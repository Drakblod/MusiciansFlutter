import 'package:flutter/foundation.dart';

/// Defines the kind of skill, instrument, role, voice, action, or legacy heading.
enum SkillOptionKind {
  role,
  instrument,
  voice,
  action,
  legacyHeader,
}

/// Identifies the application context for taxonomy retrieval.
enum SkillTaxonomyContext {
  editProfile,
  register,
  browseMusicians,
  findSub,
  collabs,
  findCollabs,
  createSession,
  producerSearch,
}

/// A single immutable skill, role, instrument, voice, or taxonomy entry.
@immutable
class SkillTaxonomyOption {
  final String id;
  final String persistedValue;
  final String displayLabel;
  final SkillOptionKind kind;
  final List<String> aliases;

  const SkillTaxonomyOption({
    required this.id,
    required this.persistedValue,
    required this.displayLabel,
    required this.kind,
    this.aliases = const [],
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SkillTaxonomyOption &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'SkillTaxonomyOption(id: $id, value: $persistedValue)';
}

/// An immutable category grouping a list of skill/instrument options.
@immutable
class SkillTaxonomyCategory {
  final String id;
  final String displayLabel;
  final String? leadingSymbol;
  final List<String> optionIds;

  const SkillTaxonomyCategory({
    required this.id,
    required this.displayLabel,
    this.leadingSymbol,
    required this.optionIds,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SkillTaxonomyCategory &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'SkillTaxonomyCategory(id: $id, label: $displayLabel)';
}

/// Result of taxonomy integrity validation.
class SkillTaxonomyValidationResult {
  final bool isValid;
  final List<String> errors;

  const SkillTaxonomyValidationResult({
    required this.isValid,
    required this.errors,
  });
}

/// Authoritative central taxonomy for skills, roles, instruments, and voices.
class SkillsTaxonomy {
  SkillsTaxonomy._();

  // ---------------------------------------------------------------------------
  // Master Options Definition (Immutable)
  // ---------------------------------------------------------------------------
  static const Map<String, SkillTaxonomyOption> _allOptions = {
    // --- Sessions / Collaboration ---
    'create_session': SkillTaxonomyOption(
      id: 'create_session',
      persistedValue: 'Create Session',
      displayLabel: 'Create Session',
      kind: SkillOptionKind.action,
    ),
    'create_jam': SkillTaxonomyOption(
      id: 'create_jam',
      persistedValue: 'Create Jam',
      displayLabel: 'Create Jam',
      kind: SkillOptionKind.action,
    ),
    'find_session': SkillTaxonomyOption(
      id: 'find_session',
      persistedValue: 'Find Session',
      displayLabel: 'Find Session',
      kind: SkillOptionKind.action,
    ),
    'studio_session': SkillTaxonomyOption(
      id: 'studio_session',
      persistedValue: 'Studio Session',
      displayLabel: 'Studio Session',
      kind: SkillOptionKind.action,
    ),
    'rehearsal_jam': SkillTaxonomyOption(
      id: 'rehearsal_jam',
      persistedValue: 'Rehearsal Jam',
      displayLabel: 'Rehearsal Jam',
      kind: SkillOptionKind.action,
    ),
    'cowriting_session': SkillTaxonomyOption(
      id: 'cowriting_session',
      persistedValue: 'Co-Writing Session',
      displayLabel: 'Co-Writing Session',
      kind: SkillOptionKind.action,
      aliases: ['Co-writing Session', 'Co-writing session'],
    ),

    // --- Roles / Production (RUTA-02 Display Labels & Hierarchy) ---
    'bandleader': SkillTaxonomyOption(
      id: 'bandleader',
      persistedValue: 'BANDLEADER',
      displayLabel: 'BANDLEADER',
      kind: SkillOptionKind.role,
      aliases: ['Bandleader', 'bandleader', 'BAND LEADER', 'Band Leader'],
    ),
    'songwriter': SkillTaxonomyOption(
      id: 'songwriter',
      persistedValue: 'SONGWRITER',
      displayLabel: 'Songwriter',
      kind: SkillOptionKind.role,
      aliases: ['Songwriter', 'songwriter', 'SONGWRITER', 'Song Writer'],
    ),
    'producer': SkillTaxonomyOption(
      id: 'producer',
      persistedValue: 'PRODUCER',
      displayLabel: 'Producer',
      kind: SkillOptionKind.role,
      aliases: ['Producer', 'producer', 'PRODUCER', 'Music Producer'],
    ),
    'composer': SkillTaxonomyOption(
      id: 'composer',
      persistedValue: 'COMPOSER',
      displayLabel: 'Composer',
      kind: SkillOptionKind.role,
      aliases: ['Composer', 'composer', 'COMPOSER'],
    ),
    'lyricist': SkillTaxonomyOption(
      id: 'lyricist',
      persistedValue: 'LYRICIST',
      displayLabel: 'Lyricist',
      kind: SkillOptionKind.role,
      aliases: ['Lyricist', 'lyricist', 'LYRICIST'],
    ),
    'beatmaker': SkillTaxonomyOption(
      id: 'beatmaker',
      persistedValue: 'BEATMAKER',
      displayLabel: 'Beatmaker',
      kind: SkillOptionKind.role,
      aliases: ['Beatmaker', 'beatmaker', 'BEATMAKER', 'Beat Maker'],
    ),
    'studio_engineer_etc': SkillTaxonomyOption(
      id: 'studio_engineer_etc',
      persistedValue: 'STUDIO/ENGINEER, etc',
      displayLabel: 'Engineer',
      kind: SkillOptionKind.role,
      aliases: [
        'Studio/Engineer',
        'studio/engineer',
        'Studio/Engineer, etc',
        'Mix Engineer',
        'mix engineer',
        'Mix engineer',
        'Recording Engineer',
        'STUDIO/ENGINEER, etc',
        'Engineer',
      ],
    ),
    'dj': SkillTaxonomyOption(
      id: 'dj',
      persistedValue: 'DJ',
      displayLabel: 'DJ',
      kind: SkillOptionKind.role,
      aliases: ['dj', 'Dj', 'Disc Jockey', 'disc jockey'],
    ),

    // --- Woodwinds ---
    'recorder': SkillTaxonomyOption(
      id: 'recorder',
      persistedValue: 'Recorder',
      displayLabel: 'Recorder',
      kind: SkillOptionKind.instrument,
    ),
    'flute': SkillTaxonomyOption(
      id: 'flute',
      persistedValue: 'Flute',
      displayLabel: 'Flute',
      kind: SkillOptionKind.instrument,
    ),
    'oboe': SkillTaxonomyOption(
      id: 'oboe',
      persistedValue: 'Oboe',
      displayLabel: 'Oboe',
      kind: SkillOptionKind.instrument,
    ),
    'clarinet': SkillTaxonomyOption(
      id: 'clarinet',
      persistedValue: 'Clarinet',
      displayLabel: 'Clarinet',
      kind: SkillOptionKind.instrument,
    ),
    'bassoon': SkillTaxonomyOption(
      id: 'bassoon',
      persistedValue: 'Bassoon',
      displayLabel: 'Bassoon',
      kind: SkillOptionKind.instrument,
    ),
    'soprano_sax': SkillTaxonomyOption(
      id: 'soprano_sax',
      persistedValue: 'Soprano Sax',
      displayLabel: 'Soprano Sax',
      kind: SkillOptionKind.instrument,
      aliases: ['Soprano Saxophone'],
    ),
    'alto_sax': SkillTaxonomyOption(
      id: 'alto_sax',
      persistedValue: 'Alto Sax',
      displayLabel: 'Alto Sax',
      kind: SkillOptionKind.instrument,
      aliases: ['Alto Saxophone'],
    ),
    'tenor_sax': SkillTaxonomyOption(
      id: 'tenor_sax',
      persistedValue: 'Tenor Sax',
      displayLabel: 'Tenor Sax',
      kind: SkillOptionKind.instrument,
      aliases: ['Tenor Saxophone'],
    ),
    'bari_sax': SkillTaxonomyOption(
      id: 'bari_sax',
      persistedValue: 'Bari Sax',
      displayLabel: 'Bari Sax',
      kind: SkillOptionKind.instrument,
      aliases: ['Baritone Sax', 'Baritone Saxophone'],
    ),

    // --- Brass ---
    'trumpet': SkillTaxonomyOption(
      id: 'trumpet',
      persistedValue: 'Trumpet',
      displayLabel: 'Trumpet',
      kind: SkillOptionKind.instrument,
    ),
    'cornet': SkillTaxonomyOption(
      id: 'cornet',
      persistedValue: 'Cornet',
      displayLabel: 'Cornet',
      kind: SkillOptionKind.instrument,
    ),
    'trombone': SkillTaxonomyOption(
      id: 'trombone',
      persistedValue: 'Trombone',
      displayLabel: 'Trombone',
      kind: SkillOptionKind.instrument,
    ),
    'french_horn': SkillTaxonomyOption(
      id: 'french_horn',
      persistedValue: 'French Horn',
      displayLabel: 'French Horn',
      kind: SkillOptionKind.instrument,
      aliases: ['Horn'],
    ),
    'euphonium': SkillTaxonomyOption(
      id: 'euphonium',
      persistedValue: 'Euphonium',
      displayLabel: 'Euphonium',
      kind: SkillOptionKind.instrument,
    ),
    'tuba': SkillTaxonomyOption(
      id: 'tuba',
      persistedValue: 'Tuba',
      displayLabel: 'Tuba',
      kind: SkillOptionKind.instrument,
    ),

    // --- Strings ---
    'violin': SkillTaxonomyOption(
      id: 'violin',
      persistedValue: 'Violin',
      displayLabel: 'Violin',
      kind: SkillOptionKind.instrument,
      aliases: ['Fiddle'],
    ),
    'viola': SkillTaxonomyOption(
      id: 'viola',
      persistedValue: 'Viola',
      displayLabel: 'Viola',
      kind: SkillOptionKind.instrument,
    ),
    'cello': SkillTaxonomyOption(
      id: 'cello',
      persistedValue: 'Cello',
      displayLabel: 'Cello',
      kind: SkillOptionKind.instrument,
      aliases: ['Violoncello'],
    ),
    'contrabass': SkillTaxonomyOption(
      id: 'contrabass',
      persistedValue: 'Contrabass',
      displayLabel: 'Contrabass',
      kind: SkillOptionKind.instrument,
      aliases: ['Double Bass', 'Upright Bass', 'Standup Bass'],
    ),
    'acoustic_guitar': SkillTaxonomyOption(
      id: 'acoustic_guitar',
      persistedValue: 'Acoustic Guitar',
      displayLabel: 'Acoustic Guitar',
      kind: SkillOptionKind.instrument,
    ),
    'electric_guitar': SkillTaxonomyOption(
      id: 'electric_guitar',
      persistedValue: 'Electric Guitar',
      displayLabel: 'Electric Guitar',
      kind: SkillOptionKind.instrument,
    ),
    'electric_bass': SkillTaxonomyOption(
      id: 'electric_bass',
      persistedValue: 'Electric Bass',
      displayLabel: 'Electric Bass',
      kind: SkillOptionKind.instrument,
      aliases: ['Bass Guitar'],
    ),
    'harp': SkillTaxonomyOption(
      id: 'harp',
      persistedValue: 'Harp',
      displayLabel: 'Harp',
      kind: SkillOptionKind.instrument,
    ),

    // --- Keyboards ---
    'piano': SkillTaxonomyOption(
      id: 'piano',
      persistedValue: 'Piano',
      displayLabel: 'Piano',
      kind: SkillOptionKind.instrument,
      aliases: ['Grand Piano', 'Upright Piano'],
    ),
    'keyboard_synth': SkillTaxonomyOption(
      id: 'keyboard_synth',
      persistedValue: 'Keyboard/Synth',
      displayLabel: 'Keyboard/Synth',
      kind: SkillOptionKind.instrument,
      aliases: ['Synthesizer', 'Synth', 'Keyboards'],
    ),
    'harpsichord': SkillTaxonomyOption(
      id: 'harpsichord',
      persistedValue: 'Harpsichord',
      displayLabel: 'Harpsichord',
      kind: SkillOptionKind.instrument,
    ),
    'organ_hammond': SkillTaxonomyOption(
      id: 'organ_hammond',
      persistedValue: 'Organ (Hammond)',
      displayLabel: 'Organ (Hammond)',
      kind: SkillOptionKind.instrument,
      aliases: ['Hammond Organ', 'Organ', 'B3 Organ'],
    ),

    // --- Percussion ---
    'drums': SkillTaxonomyOption(
      id: 'drums',
      persistedValue: 'Drums',
      displayLabel: 'Drums',
      kind: SkillOptionKind.instrument,
      aliases: ['Drum Kit', 'Drummer'],
    ),
    'latin_percussion': SkillTaxonomyOption(
      id: 'latin_percussion',
      persistedValue: 'Latin Percussion (congas, timbales, etc)',
      displayLabel: 'Latin Percussion (congas, timbales, etc)',
      kind: SkillOptionKind.instrument,
      aliases: ['Latin Percussion', 'Congas', 'Timbales'],
    ),
    'classical_percussion': SkillTaxonomyOption(
      id: 'classical_percussion',
      persistedValue: 'Classical Percussion (timpani, cymbals, etc)',
      displayLabel: 'Classical Percussion (timpani, cymbals, etc)',
      kind: SkillOptionKind.instrument,
      aliases: ['Classical Percussion', 'Timpani'],
    ),

    // --- Miscellaneous Instruments (Moved before Voices in RUTA-02) ---
    'soprano_recorder': SkillTaxonomyOption(
      id: 'soprano_recorder',
      persistedValue: 'Soprano Recorder',
      displayLabel: 'Soprano Recorder',
      kind: SkillOptionKind.instrument,
    ),
    'alto_recorder': SkillTaxonomyOption(
      id: 'alto_recorder',
      persistedValue: 'Alto Recorder',
      displayLabel: 'Alto Recorder',
      kind: SkillOptionKind.instrument,
    ),
    'tenor_recorder': SkillTaxonomyOption(
      id: 'tenor_recorder',
      persistedValue: 'Tenor Recorder',
      displayLabel: 'Tenor Recorder',
      kind: SkillOptionKind.instrument,
    ),
    'bass_recorder': SkillTaxonomyOption(
      id: 'bass_recorder',
      persistedValue: 'Bass Recorder',
      displayLabel: 'Bass Recorder',
      kind: SkillOptionKind.instrument,
    ),
    'piccolo_flute': SkillTaxonomyOption(
      id: 'piccolo_flute',
      persistedValue: 'Piccolo Flute',
      displayLabel: 'Piccolo Flute',
      kind: SkillOptionKind.instrument,
      aliases: ['Piccolo'],
    ),
    'alto_flute': SkillTaxonomyOption(
      id: 'alto_flute',
      persistedValue: 'Alto Flute',
      displayLabel: 'Alto Flute',
      kind: SkillOptionKind.instrument,
    ),
    'bass_flute': SkillTaxonomyOption(
      id: 'bass_flute',
      persistedValue: 'Bass Flute',
      displayLabel: 'Bass Flute',
      kind: SkillOptionKind.instrument,
    ),
    'english_horn': SkillTaxonomyOption(
      id: 'english_horn',
      persistedValue: 'English Horn',
      displayLabel: 'English Horn',
      kind: SkillOptionKind.instrument,
      aliases: ['Cor Anglais'],
    ),
    'eb_clarinet': SkillTaxonomyOption(
      id: 'eb_clarinet',
      persistedValue: 'Eb Clarinet',
      displayLabel: 'Eb Clarinet',
      kind: SkillOptionKind.instrument,
    ),
    'alto_clarinet': SkillTaxonomyOption(
      id: 'alto_clarinet',
      persistedValue: 'Alto Clarinet',
      displayLabel: 'Alto Clarinet',
      kind: SkillOptionKind.instrument,
    ),
    'bass_clarinet': SkillTaxonomyOption(
      id: 'bass_clarinet',
      persistedValue: 'Bass Clarinet',
      displayLabel: 'Bass Clarinet',
      kind: SkillOptionKind.instrument,
    ),
    'contra_bassoon': SkillTaxonomyOption(
      id: 'contra_bassoon',
      persistedValue: 'Contra Bassoon',
      displayLabel: 'Contra Bassoon',
      kind: SkillOptionKind.instrument,
      aliases: ['Contrabassoon'],
    ),
    'piccolo_trumpet': SkillTaxonomyOption(
      id: 'piccolo_trumpet',
      persistedValue: 'Piccolo Trumpet',
      displayLabel: 'Piccolo Trumpet',
      kind: SkillOptionKind.instrument,
    ),
    'alto_trombone': SkillTaxonomyOption(
      id: 'alto_trombone',
      persistedValue: 'Alto Trombone',
      displayLabel: 'Alto Trombone',
      kind: SkillOptionKind.instrument,
    ),
    'viola_da_gamba': SkillTaxonomyOption(
      id: 'viola_da_gamba',
      persistedValue: 'Viola da Gamba',
      displayLabel: 'Viola da Gamba',
      kind: SkillOptionKind.instrument,
    ),
    'steel_guitar': SkillTaxonomyOption(
      id: 'steel_guitar',
      persistedValue: 'Steel Guitar',
      displayLabel: 'Steel Guitar',
      kind: SkillOptionKind.instrument,
      aliases: ['Lap Steel Guitar', 'Pedal Steel Guitar'],
    ),
    'steel_pan': SkillTaxonomyOption(
      id: 'steel_pan',
      persistedValue: 'Steel Pan',
      displayLabel: 'Steel Pan',
      kind: SkillOptionKind.instrument,
      aliases: ['Steel Drum', 'Steel Drums'],
    ),

    // --- Voices (Choir) ---
    'soprano': SkillTaxonomyOption(
      id: 'soprano',
      persistedValue: 'Soprano',
      displayLabel: 'Soprano',
      kind: SkillOptionKind.voice,
    ),
    'alto': SkillTaxonomyOption(
      id: 'alto',
      persistedValue: 'Alto',
      displayLabel: 'Alto',
      kind: SkillOptionKind.voice,
    ),
    'tenor': SkillTaxonomyOption(
      id: 'tenor',
      persistedValue: 'Tenor',
      displayLabel: 'Tenor',
      kind: SkillOptionKind.voice,
    ),
    'baritone': SkillTaxonomyOption(
      id: 'baritone',
      persistedValue: 'Baritone',
      displayLabel: 'Baritone',
      kind: SkillOptionKind.voice,
    ),
    'bass': SkillTaxonomyOption(
      id: 'bass',
      persistedValue: 'Bass',
      displayLabel: 'Bass',
      kind: SkillOptionKind.voice,
    ),

    // --- Voices (Popular Music) ---
    'male_lead_vocals': SkillTaxonomyOption(
      id: 'male_lead_vocals',
      persistedValue: 'Male Lead Vocals',
      displayLabel: 'Male Lead Vocals',
      kind: SkillOptionKind.voice,
    ),
    'female_lead_vocals': SkillTaxonomyOption(
      id: 'female_lead_vocals',
      persistedValue: 'Female Lead vocals',
      displayLabel: 'Female Lead vocals',
      kind: SkillOptionKind.voice,
      aliases: ['Female Lead Vocals'],
    ),
    'male_backing_vocals': SkillTaxonomyOption(
      id: 'male_backing_vocals',
      persistedValue: 'Male Backing vocals',
      displayLabel: 'Male Backing vocals',
      kind: SkillOptionKind.voice,
      aliases: ['Male Backing Vocals'],
    ),
    'female_backing_vocals': SkillTaxonomyOption(
      id: 'female_backing_vocals',
      persistedValue: 'Female Backing vocals',
      displayLabel: 'Female Backing vocals',
      kind: SkillOptionKind.voice,
      aliases: ['Female Backing Vocals'],
    ),

    // --- Miscellaneous Voices (RUTA-02 Display Label: "🎭 Miscellaneous Voices") ---
    'mezzo_soprano': SkillTaxonomyOption(
      id: 'mezzo_soprano',
      persistedValue: 'Mezzo Soprano',
      displayLabel: 'Mezzo Soprano',
      kind: SkillOptionKind.voice,
      aliases: ['Mezzo-Soprano', 'Mezzo'],
    ),
    'contralto': SkillTaxonomyOption(
      id: 'contralto',
      persistedValue: 'Contralto',
      displayLabel: 'Contralto',
      kind: SkillOptionKind.voice,
    ),
    'counter_tenor': SkillTaxonomyOption(
      id: 'counter_tenor',
      persistedValue: 'Counter Tenor',
      displayLabel: 'Counter Tenor',
      kind: SkillOptionKind.voice,
      aliases: ['Countertenor'],
    ),

    // --- Legacy / Flat List Special Items ---
    'instruments_voices_header': SkillTaxonomyOption(
      id: 'instruments_voices_header',
      persistedValue: 'INSTRUMENTS/VOICES',
      displayLabel: 'INSTRUMENTS/VOICES',
      kind: SkillOptionKind.legacyHeader,
    ),

    // --- Context-Specific Simplified Items ---
    'generic_vocalist': SkillTaxonomyOption(
      id: 'generic_vocalist',
      persistedValue: 'Vocalist',
      displayLabel: 'Vocalist',
      kind: SkillOptionKind.voice,
      aliases: ['vocalist', 'Vocals', 'Singer'],
    ),
    'generic_guitar': SkillTaxonomyOption(
      id: 'generic_guitar',
      persistedValue: 'Guitar',
      displayLabel: 'Guitar',
      kind: SkillOptionKind.instrument,
      aliases: ['guitar'],
    ),
    'generic_saxophone': SkillTaxonomyOption(
      id: 'generic_saxophone',
      persistedValue: 'Saxophone',
      displayLabel: 'Saxophone',
      kind: SkillOptionKind.instrument,
      aliases: ['sax', 'Sax'],
    ),
    'generic_keyboard': SkillTaxonomyOption(
      id: 'generic_keyboard',
      persistedValue: 'Keyboard',
      displayLabel: 'Keyboard',
      kind: SkillOptionKind.instrument,
    ),
    'generic_all_instruments': SkillTaxonomyOption(
      id: 'generic_all_instruments',
      persistedValue: 'All Instruments',
      displayLabel: 'All Instruments',
      kind: SkillOptionKind.action,
    ),
    'generic_other': SkillTaxonomyOption(
      id: 'generic_other',
      persistedValue: 'Other',
      displayLabel: 'Other',
      kind: SkillOptionKind.action,
    ),
    'role_musician': SkillTaxonomyOption(
      id: 'role_musician',
      persistedValue: 'musician',
      displayLabel: 'musician',
      kind: SkillOptionKind.role,
      aliases: ['Musician'],
    ),
    'role_engineer': SkillTaxonomyOption(
      id: 'role_engineer',
      persistedValue: 'engineer',
      displayLabel: 'engineer',
      kind: SkillOptionKind.role,
      aliases: ['session engineer'],
    ),
  };

  // ---------------------------------------------------------------------------
  // Master Category Definitions (Exact RUTA-02 visual order)
  // ---------------------------------------------------------------------------
  static const List<SkillTaxonomyCategory> _masterCategories = [
    SkillTaxonomyCategory(
      id: 'sessions_collaboration',
      displayLabel: 'Sessions/Collaboration',
      leadingSymbol: '🤝',
      optionIds: [
        'create_session',
        'create_jam',
        'find_session',
        'studio_session',
        'rehearsal_jam',
        'cowriting_session',
      ],
    ),
    SkillTaxonomyCategory(
      id: 'roles_production',
      displayLabel: 'Roles/Production',
      leadingSymbol: '🎧',
      optionIds: [
        'bandleader',
        'songwriter',
        'producer',
        'composer',
        'lyricist',
        'beatmaker',
        'studio_engineer_etc',
        'dj',
      ],
    ),
    SkillTaxonomyCategory(
      id: 'woodwinds',
      displayLabel: 'Woodwinds',
      leadingSymbol: '🎷',
      optionIds: [
        'recorder',
        'flute',
        'oboe',
        'clarinet',
        'bassoon',
        'soprano_sax',
        'alto_sax',
        'tenor_sax',
        'bari_sax',
      ],
    ),
    SkillTaxonomyCategory(
      id: 'brass',
      displayLabel: 'Brass',
      leadingSymbol: '🎺',
      optionIds: [
        'trumpet',
        'cornet',
        'trombone',
        'french_horn',
        'euphonium',
        'tuba',
      ],
    ),
    SkillTaxonomyCategory(
      id: 'strings',
      displayLabel: 'Strings',
      leadingSymbol: '🎻',
      optionIds: [
        'violin',
        'viola',
        'cello',
        'contrabass',
        'acoustic_guitar',
        'electric_guitar',
        'electric_bass',
        'harp',
      ],
    ),
    SkillTaxonomyCategory(
      id: 'keyboards',
      displayLabel: 'Keyboards',
      leadingSymbol: '🎹',
      optionIds: [
        'piano',
        'keyboard_synth',
        'harpsichord',
        'organ_hammond',
      ],
    ),
    SkillTaxonomyCategory(
      id: 'percussion',
      displayLabel: 'Percussion',
      leadingSymbol: '🥁',
      optionIds: [
        'drums',
        'latin_percussion',
        'classical_percussion',
      ],
    ),
    SkillTaxonomyCategory(
      id: 'misc_instruments',
      displayLabel: 'Miscellaneous Instruments',
      leadingSymbol: '🪈',
      optionIds: [
        'soprano_recorder',
        'alto_recorder',
        'tenor_recorder',
        'bass_recorder',
        'piccolo_flute',
        'alto_flute',
        'bass_flute',
        'english_horn',
        'eb_clarinet',
        'alto_clarinet',
        'bass_clarinet',
        'contra_bassoon',
        'piccolo_trumpet',
        'alto_trombone',
        'viola_da_gamba',
        'steel_guitar',
        'steel_pan',
      ],
    ),
    SkillTaxonomyCategory(
      id: 'voices_choir',
      displayLabel: 'Voices (Choir)',
      leadingSymbol: '🗣️',
      optionIds: [
        'soprano',
        'alto',
        'tenor',
        'baritone',
        'bass',
      ],
    ),
    SkillTaxonomyCategory(
      id: 'voices_popular',
      displayLabel: 'Voices (Popular Music)',
      leadingSymbol: '🎤',
      optionIds: [
        'male_lead_vocals',
        'female_lead_vocals',
        'male_backing_vocals',
        'female_backing_vocals',
      ],
    ),
    SkillTaxonomyCategory(
      id: 'misc_voices',
      displayLabel: 'Miscellaneous Voices',
      leadingSymbol: '🎭',
      optionIds: [
        'mezzo_soprano',
        'contralto',
        'counter_tenor',
      ],
    ),
  ];

  // ---------------------------------------------------------------------------
  // Flat Option Sequences (Registration / Find Sub)
  // ---------------------------------------------------------------------------
  static const List<String> _flatRegistrationOptionIds = [
    'bandleader',
    'songwriter',
    'producer',
    'composer',
    'lyricist',
    'beatmaker',
    'studio_engineer_etc',
    'dj',
    'instruments_voices_header',
    'recorder',
    'flute',
    'oboe',
    'clarinet',
    'bassoon',
    'soprano_sax',
    'alto_sax',
    'tenor_sax',
    'bari_sax',
    'trumpet',
    'cornet',
    'trombone',
    'french_horn',
    'euphonium',
    'tuba',
    'violin',
    'viola',
    'cello',
    'contrabass',
    'acoustic_guitar',
    'electric_guitar',
    'electric_bass',
    'harp',
    'piano',
    'keyboard_synth',
    'harpsichord',
    'organ_hammond',
    'drums',
    'latin_percussion',
    'classical_percussion',
    'soprano',
    'alto',
    'tenor',
    'baritone',
    'bass',
    'mezzo_soprano',
    'contralto',
    'counter_tenor',
    'male_lead_vocals',
    'female_lead_vocals',
    'male_backing_vocals',
    'female_backing_vocals',
    'soprano_recorder',
    'alto_recorder',
    'tenor_recorder',
    'bass_recorder',
    'piccolo_flute',
    'alto_flute',
    'bass_flute',
    'english_horn',
    'eb_clarinet',
    'alto_clarinet',
    'bass_clarinet',
    'contra_bassoon',
    'piccolo_trumpet',
    'alto_trombone',
    'viola_da_gamba',
    'steel_guitar',
    'steel_pan',
  ];

  // ---------------------------------------------------------------------------
  // Hierarchy & Presentation Constants
  // ---------------------------------------------------------------------------
  static const String instrumentsVoicesSectionHeader = 'INSTRUMENTS/VOICES';
  static const String featuredRolePersistedValue = 'BANDLEADER';
  static const String featuredRoleDisplayLabel = 'BANDLEADER';

  /// Returns the leading visual symbol (emoji/icon) for the category if available.
  static String? getLeadingSymbolForCategory(String categoryLabelOrId) {
    for (final cat in _masterCategories) {
      if (cat.id == categoryLabelOrId ||
          cat.displayLabel == categoryLabelOrId ||
          cat.displayLabel.replaceAll(' ', '') == categoryLabelOrId.replaceAll(' ', '')) {
        return cat.leadingSymbol;
      }
    }
    return null;
  }

  // ---------------------------------------------------------------------------
  // Public Accessors & Context APIs
  // ---------------------------------------------------------------------------

  /// Returns an unmodifiable map of all registered options.
  static Map<String, SkillTaxonomyOption> get allOptions =>
      Map.unmodifiable(_allOptions);

  /// Returns an unmodifiable list of master categories.
  static List<SkillTaxonomyCategory> get masterCategories =>
      List.unmodifiable(_masterCategories);

  /// Returns the categories appropriate for the given [context].
  static List<SkillTaxonomyCategory> categoriesFor(
    SkillTaxonomyContext context,
  ) {
    switch (context) {
      case SkillTaxonomyContext.editProfile:
      case SkillTaxonomyContext.browseMusicians:
      case SkillTaxonomyContext.collabs:
      case SkillTaxonomyContext.findCollabs:
      case SkillTaxonomyContext.findSub:
        return List.unmodifiable(_masterCategories);
      case SkillTaxonomyContext.register:
      case SkillTaxonomyContext.createSession:
      case SkillTaxonomyContext.producerSearch:
        return const [];
    }
  }

  /// Returns the options appropriate for the given [context].
  static List<SkillTaxonomyOption> optionsFor(SkillTaxonomyContext context) {
    switch (context) {
      case SkillTaxonomyContext.editProfile:
      case SkillTaxonomyContext.browseMusicians:
      case SkillTaxonomyContext.collabs:
      case SkillTaxonomyContext.findCollabs:
        final options = <SkillTaxonomyOption>[];
        for (final cat in _masterCategories) {
          for (final optId in cat.optionIds) {
            final opt = _allOptions[optId];
            if (opt != null && !options.contains(opt)) {
              options.add(opt);
            }
          }
        }
        return List.unmodifiable(options);

      case SkillTaxonomyContext.findSub:
      case SkillTaxonomyContext.register:
        final options = <SkillTaxonomyOption>[];
        for (final optId in _flatRegistrationOptionIds) {
          final opt = _allOptions[optId];
          if (opt != null) {
            options.add(opt);
          }
        }
        return List.unmodifiable(options);

      case SkillTaxonomyContext.createSession:
        return List.unmodifiable([
          _allOptions['electric_guitar']!,
          _allOptions['electric_bass']!,
          _allOptions['drums']!,
          _allOptions['keyboard_synth']!,
          _allOptions['piano']!,
          _allOptions['acoustic_guitar']!,
          _allOptions['generic_vocalist']!,
        ]);

      case SkillTaxonomyContext.producerSearch:
        return List.unmodifiable([
          _allOptions['generic_all_instruments']!,
          _allOptions['generic_vocalist']!,
          _allOptions['generic_guitar']!,
          _allOptions['bass']!,
          _allOptions['drums']!,
          _allOptions['piano']!,
          _allOptions['generic_keyboard']!,
          _allOptions['generic_saxophone']!,
          _allOptions['trumpet']!,
          _allOptions['violin']!,
          _allOptions['cello']!,
          _allOptions['generic_other']!,
        ]);
    }
  }

  /// Returns a category-to-display-labels map for structured picker bottom sheets.
  static Map<String, List<String>> categoryMapFor(
    SkillTaxonomyContext context,
  ) {
    final categories = categoriesFor(context);
    final map = <String, List<String>>{};
    for (final cat in categories) {
      final items = <String>[];
      for (final optId in cat.optionIds) {
        final opt = _allOptions[optId];
        if (opt != null) {
          items.add(opt.displayLabel);
        }
      }
      map[cat.displayLabel] = List.unmodifiable(items);
    }
    return Map.unmodifiable(map);
  }

  /// Returns the ordered list of persisted string values for the given [context].
  static List<String> persistedValuesFor(SkillTaxonomyContext context) {
    switch (context) {
      case SkillTaxonomyContext.register:
      case SkillTaxonomyContext.findSub:
        return List.unmodifiable(
          _flatRegistrationOptionIds
              .map((id) => _allOptions[id]?.persistedValue ?? '')
              .where((v) => v.isNotEmpty)
              .toList(),
        );

      case SkillTaxonomyContext.createSession:
        return List.unmodifiable([
          'Electric Guitar',
          'Electric Bass',
          'Drums',
          'Keyboard/Synth',
          'Piano',
          'Acoustic Guitar',
          'Vocalist',
        ]);

      case SkillTaxonomyContext.producerSearch:
        return List.unmodifiable([
          'All Instruments',
          'Vocalist',
          'Guitar',
          'Bass',
          'Drums',
          'Piano',
          'Keyboard',
          'Saxophone',
          'Trumpet',
          'Violin',
          'Cello',
          'Other',
        ]);

      case SkillTaxonomyContext.editProfile:
      case SkillTaxonomyContext.browseMusicians:
      case SkillTaxonomyContext.collabs:
      case SkillTaxonomyContext.findCollabs:
        final values = <String>[];
        for (final cat in _masterCategories) {
          for (final optId in cat.optionIds) {
            final opt = _allOptions[optId];
            if (opt != null && !values.contains(opt.persistedValue)) {
              values.add(opt.persistedValue);
            }
          }
        }
        return List.unmodifiable(values);
    }
  }

  /// Predefined roles for Create Session.
  static List<String> get sessionRoles => List.unmodifiable(const [
        'songwriter',
        'producer',
        'engineer',
        'vocalist',
        'musician',
      ]);

  /// Predefined target instruments for Producer Search.
  static List<String> get producerTargetInstruments => List.unmodifiable(const [
        'Vocalist',
        'Guitar',
        'Bass',
        'Drums',
        'Piano',
        'Keyboard',
        'Saxophone',
        'Trumpet',
        'Violin',
        'Cello',
        'Other',
      ]);

  // ---------------------------------------------------------------------------
  // Lookup & Resolution Helpers
  // ---------------------------------------------------------------------------

  /// Normalizes a lookup key for case-insensitive and whitespace-trimmed matching.
  static String normalizeLookupKey(String value) {
    return value.trim().toLowerCase().replaceAll(RegExp(r'\s+'), ' ');
  }

  /// Exact lookup by canonical persisted value.
  static SkillTaxonomyOption? findByPersistedValue(String value) {
    for (final opt in _allOptions.values) {
      if (opt.persistedValue == value) {
        return opt;
      }
    }
    return null;
  }

  /// Finds an option by display label.
  static SkillTaxonomyOption? findByDisplayLabel(String label) {
    for (final opt in _allOptions.values) {
      if (opt.displayLabel == label) {
        return opt;
      }
    }
    return null;
  }

  /// Finds an option by internal ID.
  static SkillTaxonomyOption? findById(String id) {
    return _allOptions[id];
  }

  /// Resolves legacy, casing, alias, display label, or ID variants to the canonical [SkillTaxonomyOption].
  /// Returns `null` if the value is unknown so callers can preserve raw stored values.
  static SkillTaxonomyOption? resolveLegacyValue(String value) {
    if (value.isEmpty) return null;

    // 1. Exact match on persistedValue
    final exactPersisted = findByPersistedValue(value);
    if (exactPersisted != null) return exactPersisted;

    // 2. Exact match on displayLabel
    final exactDisplay = findByDisplayLabel(value);
    if (exactDisplay != null) return exactDisplay;

    // 3. Exact match on ID
    if (_allOptions.containsKey(value)) {
      return _allOptions[value];
    }

    final normalized = normalizeLookupKey(value);

    // 4. Case-insensitive / normalized match on displayLabel
    for (final opt in _allOptions.values) {
      if (normalizeLookupKey(opt.displayLabel) == normalized) {
        return opt;
      }
    }

    // 5. Case-insensitive / normalized match on persistedValue
    for (final opt in _allOptions.values) {
      if (normalizeLookupKey(opt.persistedValue) == normalized) {
        return opt;
      }
    }

    // 6. Match on aliases
    for (final opt in _allOptions.values) {
      for (final alias in opt.aliases) {
        if (normalizeLookupKey(alias) == normalized) {
          return opt;
        }
      }
    }

    // 7. Match on normalized ID
    for (final opt in _allOptions.values) {
      if (normalizeLookupKey(opt.id) == normalized) {
        return opt;
      }
    }

    return null;
  }

  /// Resolves a stored or display string to its canonical persisted value if known,
  /// otherwise returns the raw string unchanged to prevent data loss.
  static String resolveCanonicalPersistedValue(String rawValue) {
    final option = resolveLegacyValue(rawValue);
    return option != null ? option.persistedValue : rawValue;
  }

  /// Resolves a persisted value or raw string to its readable display label.
  static String getDisplayLabelForPersistedValue(String rawValue) {
    final option = resolveLegacyValue(rawValue);
    return option != null ? option.displayLabel : rawValue;
  }

  /// Resolves a display label to its compatible persisted value.
  static String getPersistedValueForDisplayLabel(String displayLabel) {
    final option = resolveLegacyValue(displayLabel);
    return option != null ? option.persistedValue : displayLabel;
  }

  // ---------------------------------------------------------------------------
  // Integrity Validation Helper
  // ---------------------------------------------------------------------------

  /// Performs pure assertions checking taxonomy consistency.
  static SkillTaxonomyValidationResult validateTaxonomyIntegrity() {
    final errors = <String>[];
    final seenOptionIds = <String>{};

    for (final entry in _allOptions.entries) {
      final id = entry.key;
      final opt = entry.value;

      if (id.isEmpty) {
        errors.add('Option contains empty ID key.');
      }
      if (opt.id != id) {
        errors.add('Option ID mismatch: key "$id" != opt.id "${opt.id}".');
      }
      if (seenOptionIds.contains(id)) {
        errors.add('Duplicate option ID: "$id".');
      }
      seenOptionIds.add(id);

      if (opt.persistedValue.isEmpty) {
        errors.add('Option "$id" has empty persistedValue.');
      }
      if (opt.displayLabel.isEmpty) {
        errors.add('Option "$id" has empty displayLabel.');
      }
    }

    final seenCategoryIds = <String>{};
    for (final cat in _masterCategories) {
      if (cat.id.isEmpty) {
        errors.add('Category contains empty ID.');
      }
      if (seenCategoryIds.contains(cat.id)) {
        errors.add('Duplicate category ID: "${cat.id}".');
      }
      seenCategoryIds.add(cat.id);

      final seenCatOptionIds = <String>{};
      for (final optId in cat.optionIds) {
        if (!_allOptions.containsKey(optId)) {
          errors.add(
            'Category "${cat.id}" references unknown option ID "$optId".',
          );
        }
        if (seenCatOptionIds.contains(optId)) {
          errors.add(
            'Category "${cat.id}" contains duplicate option ID "$optId".',
          );
        }
        seenCatOptionIds.add(optId);
      }
    }

    for (final optId in _flatRegistrationOptionIds) {
      if (!_allOptions.containsKey(optId)) {
        errors.add(
          'Registration flat list references unknown option ID "$optId".',
        );
      }
    }

    // Check alias collisions
    final aliasMap = <String, String>{};
    for (final opt in _allOptions.values) {
      for (final alias in opt.aliases) {
        final key = normalizeLookupKey(alias);
        if (aliasMap.containsKey(key) && aliasMap[key] != opt.id) {
          errors.add(
            'Alias collision: "$alias" is claimed by both "${aliasMap[key]}" and "${opt.id}".',
          );
        }
        aliasMap[key] = opt.id;
      }
    }

    return SkillTaxonomyValidationResult(
      isValid: errors.isEmpty,
      errors: errors,
    );
  }
}
