/// 健康科普 —— 网页 Sapphic Care 的 1:1 还原
///
/// 六条折叠条目，+ 号会转成 ×，展开/收起是补间（AnimatedSize），
/// 和网页 details 元素的默认开合观感一致。
library;

import 'package:flutter/material.dart';

import '../../theme/haven.dart';
import '../../widgets/haven_widgets.dart';

class HavenLearnView extends StatelessWidget {
  const HavenLearnView({super.key});

  static const List<List<String>> _items = <List<String>>[
    <String>[
      '01 / 拒绝容貌与身体焦虑',
      '外阴的大小、颜色、形状、左右是否对称，都没有「标准答案」。所谓「正常」，'
          '指的是一段让你舒服、没有持续疼痛或异常症状的状态，而不是和网上的图片比较。',
    ],
    <String>[
      '02 / 极简清洁原则',
      '用温水清洗外阴即可，不需要冲洗阴道内部，也不需要带香味或「杀菌」的洗液 —— '
          '它们反而可能破坏原有的菌群平衡。内裤选择透气的纯棉材质。',
    ],
    <String>[
      '03 / 疼痛不是愉悦的代价',
      '任何形式的身体亲密，包括自我愉悦以及女孩之间的互动，都不应该以疼痛为前提。'
          '如果出现刺痛、灼烧、出血、事后持续不适，请停止并记录下来，及时就医。',
    ],
    <String>[
      '04 / 彼此尊重与知情同意',
      '在女孩与女孩的亲密关系中，同意同样需要是清楚的、自愿的、可以随时撤回的。'
          '沉默、犹豫、被迫都不是同意。你有绝对的权利在任何时候说「停下」。',
    ],
    <String>[
      '05 / 卫生与器具安全',
      '润滑剂优先选择水基配方；器具使用前后必须彻底清洁，绝不与他人共用；'
          '避开破损的皮肤。任何让你产生不适的产品都应立刻停用。',
    ],
    <String>[
      '06 / 必须就医的预警信号',
      '异常出血、持续异味、瘙痒超过一周、摸到新出现的肿块、排尿疼痛或发热。'
          '记下症状出现的时间与变化，这能帮助医生更快做出准确判断。',
    ],
  ];

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;

    return ListView(
      padding: EdgeInsets.fromLTRB(20, 6, 20, 30 + bottom),
      physics: const BouncingScrollPhysics(
        parent: AlwaysScrollableScrollPhysics(),
      ),
      children: <Widget>[
        FadeUpIn(
          child: HavenSectionTitle(
            title: 'Sapphic Care',
            note: '女性呵护女性的科普，不替代医生',
          ),
        ),
        for (int i = 0; i < _items.length; i++)
          FadeUpIn(
            delay: Duration(milliseconds: 50 * i),
            child: HavenExpandTile(
              title: _items[i][0],
              body: _items[i][1],
              initiallyOpen: i == 0,
            ),
          ),
        const SizedBox(height: 18),
        Text(
          'DISCLAIMER：内容为一般性健康科普，不构成医疗建议。'
          '如有身体不适，请咨询专业医生。本站面向 18 岁以上成年女性。',
          style: HavenColors.footnote,
        ),
      ],
    );
  }
}
