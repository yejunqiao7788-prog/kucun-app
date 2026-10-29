import 'package:flutter_test/flutter_test.dart';

import 'package:kucun_app/data/entities.dart';

/// 照抄 `getPlansForAllChannels()`（yuanbaokucun/server/business-core/services/payments.js）
/// 的出参形状：两条通道嵌在 `channels` 对象底下，不是顶层键。
Map<String, Object?> plansPayload({
  bool monobankPayable = true,
  bool paddlePayable = true,
}) =>
    <String, Object?>{
      'default_channel': monobankPayable ? 'monobank' : (paddlePayable ? 'paddle' : null),
      'channels': <String, Object?>{
        'monobank': <String, Object?>{
          'provider': 'monobank',
          'currency': 'UAH',
          'enabled': monobankPayable,
          'configured': monobankPayable,
          'payable': monobankPayable,
          'tokenization_enabled': false,
          'plans': <Object?>[
            <String, Object?>{'planType': 'monthly', 'days': 30, 'priceMinor': 5800},
            <String, Object?>{'planType': 'yearly', 'days': 365, 'priceMinor': 56000},
          ],
        },
        'paddle': <String, Object?>{
          'provider': 'paddle',
          'currency': 'USD',
          'environment': 'production',
          'configured': paddlePayable,
          'payable': paddlePayable,
          'plans': <Object?>[
            <String, Object?>{'planType': 'monthly', 'days': 30, 'priceMinor': 2999},
          ],
        },
      },
    };

void main() {
  test('档位从 channels 嵌套层读出来，两条通道都摊平成行', () {
    final PlanBoard board = PlanBoard(plansPayload());

    expect(board.channels.length, 2);
    expect(board.anyPayable, isTrue);

    final PlanChannel mono = board.channel('monobank');
    expect(mono.name, 'monobank');
    expect(mono.currency, 'UAH');
    expect(mono.payable, isTrue);
    expect(mono.plans.map((PlanRow r) => r.planType), <String>['monthly', 'yearly']);
    expect(mono.plans.first.amount, 58.0);
    expect(mono.plans.first.hasPrice, isTrue);

    final PlanChannel paddle = board.channel('paddle');
    expect(paddle.currency, 'USD');
    expect(paddle.environment, 'production');
    expect(paddle.plans.single.amount, 29.99);
  });

  test('paddle 没有 enabled 开关，缺键时按「可付即可用」处理', () {
    final PlanChannel paddle = PlanBoard(plansPayload()).channel('paddle');
    expect(paddle.json.containsKey('enabled'), isFalse);
    expect(paddle.enabled, isTrue);
  });

  test('两条都关档时才判定为无可用通道', () {
    final PlanBoard board =
        PlanBoard(plansPayload(monobankPayable: false, paddlePayable: false));
    expect(board.anyPayable, isFalse);
    expect(board.defaultChannel, isNull);
    expect(board.payableDefault, isNull);
    // 通道仍然要摊得出来，界面才分得清「没配」和「业主关掉了」。
    expect(board.channels.length, 2);
    expect(board.channel('monobank').payable, isFalse);
  });

  test('default_channel 指向可付的那一条', () {
    final PlanBoard board =
        PlanBoard(plansPayload(monobankPayable: false, paddlePayable: true));
    expect(board.defaultChannel, 'paddle');
    expect(board.payableDefault?.name, 'paddle');
  });

  test('通道整段缺失时不崩，读成无可用通道', () {
    const PlanBoard board = PlanBoard(<String, Object?>{});
    expect(board.channels, isEmpty);
    expect(board.anyPayable, isFalse);
  });
}
