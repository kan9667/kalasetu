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
      photoPath: fields[6] as String,
      category: fields[7] as String,
      tags: (fields[8] as List).cast<String>(),
      status: fields[9] as ProductStatus,
      createdAt: fields[10] as DateTime?,
      additionalPhotoPaths: (fields[11] as List).cast<String>(),
      aiEnhancedPhotoPath: fields[12] as String,
      statusUpdatedAt: fields[13] as DateTime?,
      restockQuantity: fields[14] as int?,
      statusReason: fields[15] as String?,
      revision: fields[16] == null ? 1 : fields[16] as int,
      approvedRevision: fields[17] as int?,
      approvedAt: fields[18] as DateTime?,
      approvedByArtisanId: fields[19] as String?,
      publishedAt: fields[20] as DateTime?,
      contentHash: fields[21] as String?,
      mediaId: fields[22] as String?,
      floorPrice: fields[23] as double?,
      materialsCost: fields[24] as double?,
      laborHours: fields[25] as double?,
      hourlyRate: fields[26] as double?,
      transportCost: fields[27] as double?,
      otherOverhead: fields[28] as double?,
    );
  }

  @override
  void write(BinaryWriter writer, Product obj) {
    writer
      ..writeByte(29)
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
      ..write(obj.photoPath)
      ..writeByte(7)
      ..write(obj.category)
      ..writeByte(8)
      ..write(obj.tags)
      ..writeByte(9)
      ..write(obj.status)
      ..writeByte(10)
      ..write(obj.createdAt)
      ..writeByte(11)
      ..write(obj.additionalPhotoPaths)
      ..writeByte(12)
      ..write(obj.aiEnhancedPhotoPath)
      ..writeByte(13)
      ..write(obj.statusUpdatedAt)
      ..writeByte(14)
      ..write(obj.restockQuantity)
      ..writeByte(15)
      ..write(obj.statusReason)
      ..writeByte(16)
      ..write(obj.revision)
      ..writeByte(17)
      ..write(obj.approvedRevision)
      ..writeByte(18)
      ..write(obj.approvedAt)
      ..writeByte(19)
      ..write(obj.approvedByArtisanId)
      ..writeByte(20)
      ..write(obj.publishedAt)
      ..writeByte(21)
      ..write(obj.contentHash)
      ..writeByte(22)
      ..write(obj.mediaId)
      ..writeByte(23)
      ..write(obj.floorPrice)
      ..writeByte(24)
      ..write(obj.materialsCost)
      ..writeByte(25)
      ..write(obj.laborHours)
      ..writeByte(26)
      ..write(obj.hourlyRate)
      ..writeByte(27)
      ..write(obj.transportCost)
      ..writeByte(28)
      ..write(obj.otherOverhead);
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
      case 3:
        return ProductStatus.sold;
      case 4:
        return ProductStatus.soldOut;
      case 5:
        return ProductStatus.listingRemoved;
      case 6:
        return ProductStatus.awaitingApproval;
      case 7:
        return ProductStatus.approved;
      case 8:
        return ProductStatus.published;
      case 9:
        return ProductStatus.superseded;
      case 10:
        return ProductStatus.rejected;
      case 11:
        return ProductStatus.legacyUnverified;
      case 12:
        return ProductStatus.pendingApprovalSync;
      case 13:
        return ProductStatus.pendingUnpublishSync;
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
      case ProductStatus.sold:
        writer.writeByte(3);
        break;
      case ProductStatus.soldOut:
        writer.writeByte(4);
        break;
      case ProductStatus.listingRemoved:
        writer.writeByte(5);
        break;
      case ProductStatus.awaitingApproval:
        writer.writeByte(6);
        break;
      case ProductStatus.approved:
        writer.writeByte(7);
        break;
      case ProductStatus.published:
        writer.writeByte(8);
        break;
      case ProductStatus.superseded:
        writer.writeByte(9);
        break;
      case ProductStatus.rejected:
        writer.writeByte(10);
        break;
      case ProductStatus.legacyUnverified:
        writer.writeByte(11);
        break;
      case ProductStatus.pendingApprovalSync:
        writer.writeByte(12);
        break;
      case ProductStatus.pendingUnpublishSync:
        writer.writeByte(13);
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
