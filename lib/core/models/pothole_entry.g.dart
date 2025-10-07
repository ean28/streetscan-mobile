// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'pothole_entry.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class PotholeEntryAdapter extends TypeAdapter<PotholeEntry> {
  @override
  final int typeId = 1;

  @override
  PotholeEntry read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return PotholeEntry(
      id: fields[0] as String?,
      imagePath: fields[1] as String,
      latitude: fields[2] as double,
      longitude: fields[3] as double,
      timestamp: fields[4] as DateTime,
      sessionId: fields[7] as String,
      confidence: fields[5] as double?,
      detectedClass: fields[6] as String?,
      deviceModel: fields[8] as String?,
      inferenceTime: fields[9] as int?,
      imageUrl: fields[10] as String?,
    );
  }

  @override
  void write(BinaryWriter writer, PotholeEntry obj) {
    writer
      ..writeByte(11)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.imagePath)
      ..writeByte(2)
      ..write(obj.latitude)
      ..writeByte(3)
      ..write(obj.longitude)
      ..writeByte(4)
      ..write(obj.timestamp)
      ..writeByte(5)
      ..write(obj.confidence)
      ..writeByte(6)
      ..write(obj.detectedClass)
      ..writeByte(7)
      ..write(obj.sessionId)
      ..writeByte(8)
      ..write(obj.deviceModel)
      ..writeByte(9)
      ..write(obj.inferenceTime)
      ..writeByte(10)
      ..write(obj.imageUrl);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PotholeEntryAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
