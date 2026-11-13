import 'dart:async';

import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../data/models/collection.dart';
import '../../data/models/track.dart';
import '../../data/repositories/library_repository.dart';
import '../../data/repositories/music_repository.dart';

enum CollectionStatus { loading, ready, empty, error }

class CollectionState extends Equatable {
  const CollectionState({
    this.status = CollectionStatus.loading,
    this.collection,
    this.tracks = const [],
    this.description,
    this.artistBio,
    this.similarArtists = const [],
    this.errorText,
  });

  final CollectionStatus status;
  final Collection? collection;
  final List<Track> tracks;
  final String? description;
  final String? artistBio;
  final List<Collection> similarArtists;
  final String? errorText;

  @override
  List<Object?> get props => [
    status,
    collection,
    tracks,
    description,
    artistBio,
    similarArtists,
    errorText,
  ];
}

/// Loads one album / playlist / chart / genre / artist into a playable list.
class CollectionCubit extends Cubit<CollectionState> {
  CollectionCubit({
    required MusicRepository music,
    required LibraryRepository library,
    required Collection collection,
  })  : _music = music,
        _library = library,
        _seed = collection,
        super(CollectionState(collection: collection)) {
    load();
  }

  final MusicRepository _music;
  final LibraryRepository _library;
  final Collection _seed;

  Future<void> load() async {
    emit(CollectionState(collection: _seed, status: CollectionStatus.loading));
    try {
      final detail = await _music.loadCollection(_seed);
      if (isClosed) return;

      if (detail == null || detail.tracks.isEmpty) {
        emit(
          CollectionState(
            collection: _seed,
            status: CollectionStatus.empty,
            errorText: 'NOTHING PLAYABLE IN THIS COLLECTION',
          ),
        );
        return;
      }

      final resolvedCollection = _seed.kind == CollectionKind.mix ||
              _seed.title == 'Weekly Mix' ||
              _seed.title == 'Chill Out'
          ? detail.collection.copyWith(
              title: _seed.title,
              subtitle: _seed.subtitle.isNotEmpty
                  ? _seed.subtitle
                  : detail.collection.subtitle,
            )
          : detail.collection;
      unawaited(_library.recordCollection(resolvedCollection));
      emit(
        CollectionState(
          collection: resolvedCollection,
          tracks: detail.tracks,
          description: detail.description,
          artistBio: detail.artistBio,
          similarArtists: detail.similarArtists,
          status: CollectionStatus.ready,
        ),
      );
    } catch (e) {
      if (isClosed) return;
      emit(
        CollectionState(
          collection: _seed,
          status: CollectionStatus.error,
          errorText: 'COULD NOT LOAD THIS COLLECTION',
        ),
      );
    }
  }
}
