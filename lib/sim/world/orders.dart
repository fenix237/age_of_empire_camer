/// Types d'ordres exécutables par une unité.
/// `deposit` : aller vider la charge portée (source épuisée), sans cible.
enum OrderKind { move, gather, build, repair, attack, garrison, deposit }

/// Un ordre dans la file d'une unité. `a`/`b` : case (x, y) pour `move`,
/// sinon `a` = identifiant de la cible.
class Order {
  const Order(this.kind, this.a, [this.b = 0]);

  factory Order.move(int tx, int ty) => Order(OrderKind.move, tx, ty);
  factory Order.gather(int id) => Order(OrderKind.gather, id);
  factory Order.build(int id) => Order(OrderKind.build, id);
  factory Order.repair(int id) => Order(OrderKind.repair, id);
  factory Order.attack(int id) => Order(OrderKind.attack, id);
  factory Order.garrison(int id) => Order(OrderKind.garrison, id);

  final OrderKind kind;
  final int a;
  final int b;

  bool get hasTargetId => kind != OrderKind.move && kind != OrderKind.deposit;

  List<int> toJson() => <int>[kind.index, a, b];

  static Order fromJson(Object? json) {
    final l = json! as List<dynamic>;
    return Order(OrderKind.values[l[0] as int], l[1] as int, l[2] as int);
  }

  @override
  bool operator ==(Object other) =>
      other is Order && other.kind == kind && other.a == a && other.b == b;

  @override
  int get hashCode => Object.hash(kind, a, b);

  @override
  String toString() => 'Order(${kind.name}, $a, $b)';
}
