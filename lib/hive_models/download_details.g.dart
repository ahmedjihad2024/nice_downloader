// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'download_details.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class DownloadDetailsAdapter extends TypeAdapter<DownloadDetails> {
  @override
  final int typeId = 1;

  @override
  DownloadDetails read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return DownloadDetails(
      fullPath: fields[0] as String,
      millisecondsSinceEpoch: fields[1] as int,
      url: fields[2] as String,
      totalBytes: fields[3] as int,
    );
  }

  @override
  void write(BinaryWriter writer, DownloadDetails obj) {
    writer
      ..writeByte(4)
      ..writeByte(0)
      ..write(obj.fullPath)
      ..writeByte(1)
      ..write(obj.millisecondsSinceEpoch)
      ..writeByte(2)
      ..write(obj.url)
      ..writeByte(3)
      ..write(obj.totalBytes);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DownloadDetailsAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
