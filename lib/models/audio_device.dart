class AudioDevice {
  final String id;
  final String name;
  final String kind;

  AudioDevice({required this.id, required this.name, required this.kind});

  factory AudioDevice.fromMap(Map<String, dynamic> map) {
    return AudioDevice(
      id: map['id'] ?? '',
      name: map['name'] ?? '',
      kind: map['kind'] ?? '',
    );
  }

  Map<String, dynamic> toMap() {
    return {'id': id, 'name': name, 'kind': kind};
  }

  @override
  String toString() => 'AudioDevice(id: $id, name: $name, kind: $kind)';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AudioDevice &&
        other.id == id &&
        other.name == name &&
        other.kind == kind;
  }

  @override
  int get hashCode => id.hashCode ^ name.hashCode ^ kind.hashCode;
}
