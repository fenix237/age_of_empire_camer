/// Tas-min d'entiers avec départage déterministe (priorité, puis valeur).
///
/// Chaque élément est un entier « valeur » (index de case, par exemple) associé
/// à une priorité. Aucune allocation d'objet par élément.
class MinHeap {
  final List<int> _prio = <int>[];
  final List<int> _val = <int>[];

  bool get isEmpty => _val.isEmpty;
  bool get isNotEmpty => _val.isNotEmpty;
  int get length => _val.length;

  void clear() {
    _prio.clear();
    _val.clear();
  }

  void add(int priority, int value) {
    _prio.add(priority);
    _val.add(value);
    var i = _val.length - 1;
    while (i > 0) {
      final p = (i - 1) >> 1;
      if (_less(i, p)) {
        _swap(i, p);
        i = p;
      } else {
        break;
      }
    }
  }

  /// Retire et renvoie la valeur de plus faible priorité.
  int removeFirst() {
    final top = _val.first;
    final lastV = _val.removeLast();
    final lastP = _prio.removeLast();
    if (_val.isNotEmpty) {
      _val[0] = lastV;
      _prio[0] = lastP;
      var i = 0;
      final n = _val.length;
      while (true) {
        final l = 2 * i + 1;
        final r = l + 1;
        var m = i;
        if (l < n && _less(l, m)) m = l;
        if (r < n && _less(r, m)) m = r;
        if (m == i) break;
        _swap(i, m);
        i = m;
      }
    }
    return top;
  }

  bool _less(int a, int b) =>
      _prio[a] < _prio[b] || (_prio[a] == _prio[b] && _val[a] < _val[b]);

  void _swap(int a, int b) {
    final tp = _prio[a];
    _prio[a] = _prio[b];
    _prio[b] = tp;
    final tv = _val[a];
    _val[a] = _val[b];
    _val[b] = tv;
  }
}
