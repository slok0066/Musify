import 'package:equatable/equatable.dart';

import 'track.dart';

/// A user-created playlist, persisted in Hive.
class UserPlaylist extends Equatable {
  const UserPlaylist({
    required this.id,
    required this.name,
    this.description = '',
    this.tracks = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final String name;
  final String description;
  final List<Track> tracks;
  final DateTime createdAt;
  final DateTime updatedAt;

  int get length => tracks.length;

  Duration get totalDuration =>
      tracks.fold(Duration.zero, (sum, t) => sum + t.duration);

  /// The 2×2 mosaic cover is generated from the first four songs, exactly as
  /// the PRD specifies — so an empty playlist has no fake artwork.
  List<String> get mosaicArtwork {
    final urls = <String>[];
    for (final t in tracks) {
      if (t.imageUrl.isNotEmpty && !urls.contains(t.imageUrl)) {
        urls.add(t.imageUrl);
      }
      if (urls.length == 4) break;
    }
    return urls;
  }

  UserPlaylist copyWith({
    String? id,
    String? name,
    String? description,
    List<Track>? tracks,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return UserPlaylist(
      id: id ?? this.id,
      name: name ?? this.name,
      description: description ?? this.description,
      tracks: tracks ?? this.tracks,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toMap() => {
    'id': id,
    'name': name,
    'description': description,
    'tracks': Track.listTo(tracks),
    'createdAt': createdAt.millisecondsSinceEpoch,
    'updatedAt': updatedAt.millisecondsSinceEpoch,
  };

  static UserPlaylist? fromMap(Object? raw) {
    if (raw is! Map) return null;
    final map = raw.cast<Object?, Object?>();
    final id = map['id']?.toString() ?? '';
    final name = map['name']?.toString() ?? '';
    if (id.isEmpty || name.isEmpty) return null;
    final created = map['createdAt'];
    final updated = map['updatedAt'];
    return UserPlaylist(
      id: id,
      name: name,
      description: map['description']?.toString() ?? '',
      tracks: Track.listFrom(map['tracks']),
      createdAt: created is num
          ? DateTime.fromMillisecondsSinceEpoch(created.toInt())
          : DateTime.now(),
      updatedAt: updated is num
          ? DateTime.fromMillisecondsSinceEpoch(updated.toInt())
          : DateTime.now(),
    );
  }

  @override
  List<Object?> get props => [id, name, description, tracks, updatedAt];
}
