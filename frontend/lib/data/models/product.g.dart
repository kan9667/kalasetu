// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'product.dart';

// **************************************************************************
// TypeAdapterGenerator
// **************************************************************************

class ProductAdapter extends TypeAdapter<Product> {
  @override
  final int typeId = 0;

  @override
  Product read(BinaryReader reader) {
    final numOfFields = reader.readByte();
    final fields = <int, dynamic>{
      for (int i = 0; i < numOfFields; i++) reader.readByte(): reader.read(),
    };
    return Product(
      id: fields[0] as String,
      title: fields[1] as String,
      titleHi: fields[2] as String,
      description: fields[3] as String,
      descriptionHi: fields[4] as String,
      price: fields[5] as double,
      imageUrl: fields[6] as String,
      category: fields[7] as String,
      tags: (fields[8] as List).cast<String>(),
      status: fields[9] as ProductStatus,
      createdAt: fields[10] as DateTime?,
    );
  }

  @override
  void write(BinaryWriter writer, Product obj) {
    writer
      ..writeByte(11)
      ..writeByte(0)
      ..write(obj.id)
      ..writeByte(1)
      ..write(obj.title)
      ..writeByte(2)
      ..write(obj.titleHi)
      ..writeByte(3)
      ..write(obj.description)
      ..writeByte(4)
      ..write(obj.descriptionHi)
      ..writeByte(5)
      ..write(obj.price)
      ..writeByte(6)
      ..write(obj.imageUrl)
      ..writeByte(7)
      ..write(obj.category)
      ..writeByte(8)
      ..write(obj.tags)
      ..writeByte(9)
      ..write(obj.status)
      ..writeByte(10)
      ..write(obj.createdAt);
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProductAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}

class ProductStatusAdapter extends TypeAdapter<ProductStatus> {
  @override
  final int typeId = 1;

  @override
  ProductStatus read(BinaryReader reader) {
    switch (reader.readByte()) {
      case 0:
        return ProductStatus.live;
      case 1:
        return ProductStatus.pendingSync;
      case 2:
        return ProductStatus.draft;
      default:
        return ProductStatus.live;
    }
  }

  @override
  void write(BinaryWriter writer, ProductStatus obj) {
    switch (obj) {
      case ProductStatus.live:
        writer.writeByte(0);
        break;
      case ProductStatus.pendingSync:
        writer.writeByte(1);
        break;
      case ProductStatus.draft:
        writer.writeByte(2);
        break;
    }
  }

  @override
  int get hashCode => typeId.hashCode;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ProductStatusAdapter &&
          runtimeType == other.runtimeType &&
          typeId == other.typeId;
}
