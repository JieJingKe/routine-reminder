/// 顶栏的三段切换。
///
/// 三个视图共用同一份 `AppData`，切换只是换密度，不重载数据，
/// 也不丢编辑到一半的改动（需求：L1 与 L2 是同一块区域的两种密度）。
enum AppView {
  dashboard('看板'),
  edit('编辑'),
  summary('汇总');

  const AppView(this.label);

  final String label;
}
