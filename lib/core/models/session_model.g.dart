// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'session_model.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class SessionModelAdapter extends TypeAdapter<SessionModel> {
  @override
  final int typeId = 0;

  @override
  SessionModel read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return SessionModel(
      id: fields[0] as String?,
      createdAt: fields[1] as DateTime,
      durationSeconds: fields[2] as int,
      entries: (fields[3] as List?)?.cast<PotholeEntry>(),
      pendingUpload: fields[4] as bool,
      averageLatency: fields[5] as double?,
      totalFramesProcessed: fields[6] as int?,
      gpsTrack: (fields[7] as List?)
          ?.map((dynamic e) => (e as Map).cast<String, double>())
          ?.toList(),
      potholeSeverityCounts: (fields[8] as Map?)?.cast<String, int>(),
    );
  }

  @override
  void write(BinaryWriter writer, SessionModel obj) {
    writer
      ..writeByte(9)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.createdAt)
      ..writeByte(2)
      ..write(obj.durationSeconds)
      ..writeByte(3)
      ..write(obj.entries)
      ..writeByte(4)
      ..write(obj.pendingUpload)
      ..writeByte(5)
      ..write(obj.averageLatency)
      ..writeByte(6)
      ..write(obj.totalFramesProcessed)
      ..writeByte(7)
      ..write(obj.gpsTrack)
      ..writeByte(8)
      ..write(obj.potholeSeverityCounts);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is SessionModelAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
