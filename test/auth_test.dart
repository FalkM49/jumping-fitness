import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jumping_fitness/auth/auth_repository.dart';
import 'package:jumping_fitness/auth/email_address.dart';
import 'package:jumping_fitness/auth/firebase_auth_repository.dart';
import 'package:jumping_fitness/auth/full_name.dart';
import 'package:jumping_fitness/auth/login_controller.dart';
import 'package:jumping_fitness/auth/phone_number.dart';
import 'package:jumping_fitness/auth/session.dart';
import 'package:jumping_fitness/models/user_profile.dart';
import 'package:jumping_fitness/services/backend_providers.dart';
import 'package:jumping_fitness/services/trainer_requests_repository.dart';
import 'package:jumping_fitness/utils/ru_format.dart';

import 'support/fakes.dart';

void main() {
  group('PhoneNumber.normalize', () {
    test('российский номер в любом привычном виде → E.164', () {
      for (final input in [
        '9991234567',
        '89991234567',
        '79991234567',
        '8 (999) 123-45-67',
        '+7 999 123 45 67',
        ' +7(999)123-45-67 ',
      ]) {
        expect(PhoneNumber.normalize(input), '+79991234567', reason: input);
      }
    });

    test('международный номер с «+»', () {
      expect(PhoneNumber.normalize('+375 29 123-45-67'), '+375291234567');
      expect(PhoneNumber.normalize('+7 701 123 4567'), '+77011234567');
    });

    test('неполный или лишний номер — null', () {
      for (final input in [
        '',
        '999123456',
        '899912345678',
        '59991234567',
        '+7 999 123 45 6',
        '+1234',
        '+0123456789',
      ]) {
        expect(PhoneNumber.normalize(input), isNull, reason: input);
      }
    });

    test('показ номера', () {
      expect(PhoneNumber.format('+79991234567'), '+7 999 123-45-67');
      expect(PhoneNumber.format('+375291234567'), '+375291234567');
    });
  });

  group('ФИО', () {
    test('подсказки под полем', () {
      expect(fullNameError('  Смирнова Анна Сергеевна '), isNull);
      expect(fullNameError('   '), 'Введите ФИО.');
      expect(fullNameError('Ян'), contains('минимум 3'));
      expect(fullNameError('Я' * 101), contains('не больше 100'));
      expect(fullNameError('Анна\nСмирнова'), contains('переносы строк'));
    });

    test('принятое ФИО проходит и проверку правил Firestore', () {
      for (final name in ['Ян Ли', 'Анна-Мария Ёлкина', 'Я' * 100]) {
        expect(fullNameError(name), isNull);
        expect(UserProfile.isValidFullName(name.trim()), isTrue);
      }
    });
  });

  test('коды ошибок Firebase Auth → понятные причины', () {
    expect(
      authFailureKindForCode('invalid-credential'),
      AuthFailureKind.wrongCredentials,
    );
    expect(
      authFailureKindForCode('wrong-password'),
      AuthFailureKind.wrongCredentials,
    );
    expect(
      authFailureKindForCode('invalid-email'),
      AuthFailureKind.invalidEmail,
    );
    expect(
      authFailureKindForCode('email-already-in-use'),
      AuthFailureKind.emailInUse,
    );
    expect(
      authFailureKindForCode('weak-password'),
      AuthFailureKind.weakPassword,
    );
    expect(
      authFailureKindForCode('too-many-requests'),
      AuthFailureKind.tooManyRequests,
    );
    expect(
      authFailureKindForCode('network-request-failed'),
      AuthFailureKind.network,
    );
    expect(authFailureKindForCode('что-то новое'), AuthFailureKind.unknown);
    for (final kind in AuthFailureKind.values) {
      expect(kind.message, isNotEmpty);
    }
  });

  group('почта и пароль', () {
    test('адрес обрезается и приводится к нижнему регистру', () {
      expect(EmailAddress.normalize('  Anna.S@Mail.RU '), 'anna.s@mail.ru');
      for (final bad in [
        '',
        'anna',
        'anna@mail',
        '@mail.ru',
        'an na@mail.ru',
      ]) {
        expect(EmailAddress.normalize(bad), isNull, reason: bad);
      }
    });

    test('пароль нового аккаунта — от 8 до 128 символов', () {
      expect(newPasswordError('1234567'), isNotNull);
      expect(newPasswordError('12345678'), isNull);
      expect(newPasswordError('x' * 129), isNotNull);
    });
  });
  test('даты по Москве', () {
    final instant = DateTime.utc(2026, 12, 31, 21, 30);
    expect(RuFormat.date(instant), '1 января 2027');
    expect(RuFormat.dateTime(instant), '1 января 2027, 00:30');
    expect(RuFormat.countdown(60), '1:00');
    expect(RuFormat.countdown(9), '0:09');
  });

  test('заявки: раньше поданные выше, без даты — в конце', () {
    final sorted = sortedByCreation([
      request(uid: 'c'),
      request(uid: 'b', createdAt: DateTime.utc(2026, 9, 2)),
      request(uid: 'a', createdAt: DateTime.utc(2026, 9, 1)),
    ]);
    expect(sorted.map((r) => r.uid), ['a', 'b', 'c']);
  });

  group('сессия', () {
    ProviderContainer container(FakeAuthRepository auth, FakeBackend backend) {
      final c = ProviderContainer(
        overrides: [
          authRepositoryProvider.overrideWithValue(auth),
          userRepositoryProvider.overrideWithValue(backend),
        ],
      );
      addTearDown(c.dispose);
      // Держим подписку, чтобы потоки не отписывались между проверками.
      c.listen(sessionProvider, (_, _) {});
      return c;
    }

    /// Даём потокам-подделкам и провайдерам доставить события.
    Future<void> settle() async {
      for (var i = 0; i < 5; i++) {
        await Future<void>.delayed(Duration.zero);
      }
    }

    test('выход → нужна регистрация → клиент → тренер', () async {
      final auth = FakeAuthRepository();
      final backend = FakeBackend();
      final c = container(auth, backend);

      expect(c.read(sessionProvider), isA<SessionLoading>());
      await settle();
      expect(c.read(sessionProvider), isA<SignedOut>());

      auth.signInAs('+79991234567');
      await settle();
      await settle();
      expect(c.read(sessionProvider), isA<NeedsRegistration>());

      final uid = FakeAuthRepository.uidFor('+79991234567');
      backend.putProfile(profile(uid: uid));
      await settle();
      final client = c.read(sessionProvider) as SignedIn;
      expect(client.home, HomeKind.client);

      backend.putProfile(profile(uid: uid, role: UserRole.trainer));
      await settle();
      expect((c.read(sessionProvider) as SignedIn).home, HomeKind.trainer);
    });

    test('админ с ролью client — экран тренера', () async {
      final auth = FakeAuthRepository()..signInAs('+79990000009');
      final backend = FakeBackend()
        ..putProfile(
          profile(
            uid: FakeAuthRepository.uidFor('+79990000009'),
            isAdmin: true,
          ),
        );
      final c = container(auth, backend);
      await settle();
      await settle();
      expect((c.read(sessionProvider) as SignedIn).home, HomeKind.trainer);
    });

    test('отпечаток меняется при смене роли и флага админа', () {
      const user = AuthUser(uid: 'u', email: 'u@mail.ru');
      final client = SignedIn(user, profile(uid: 'u'));
      final trainer = SignedIn(user, profile(uid: 'u', role: UserRole.trainer));
      final admin = SignedIn(user, profile(uid: 'u', isAdmin: true));
      final fingerprints = {
        sessionFingerprint(client),
        sessionFingerprint(trainer),
        sessionFingerprint(admin),
        sessionFingerprint(const SignedOut()),
        sessionFingerprint(const NeedsRegistration(user)),
        sessionFingerprint(const NeedsEmailVerification(user)),
      };
      expect(fingerprints, hasLength(6));
      expect(
        sessionFingerprint(client),
        sessionFingerprint(
          SignedIn(user, profile(uid: 'u', fullName: 'Другое')),
        ),
      );
    });
  });

  group('LoginController', () {
    late FakeAuthRepository auth;
    late ProviderContainer c;

    setUp(() {
      auth = FakeAuthRepository();
      c = ProviderContainer(
        overrides: [authRepositoryProvider.overrideWithValue(auth)],
      );
      c.listen(loginControllerProvider, (_, _) {});
    });

    tearDown(() => c.dispose());

    LoginController controller() => c.read(loginControllerProvider.notifier);
    LoginState state() => c.read(loginControllerProvider);

    test('двойное нажатие не создаёт два аккаунта', () async {
      controller().setMode(LoginMode.signUp);
      final first = controller().signUp('a@mail.ru', '12345678', '12345678');
      final second = controller().signUp('a@mail.ru', '12345678', '12345678');
      await Future.wait([first, second]);
      expect(auth.signUpCalls, 1);
      expect(state().error, isNull);
    });

    test('ошибка сервера показывается и сбрасывается при вводе', () async {
      auth.nextFailure = const AuthFailure(AuthFailureKind.network);
      await controller().signIn('a@mail.ru', 'пароль');
      expect(state().error, AuthFailureKind.network.message);
      controller().clearErrors();
      expect(state().error, isNull);
    });

    test('смена режима очищает ошибки и сообщения', () async {
      await controller().resetPassword('a@mail.ru');
      expect(state().info, isNotNull);
      controller().setMode(LoginMode.signIn);
      expect(state().info, isNull);
      expect(state().mode, LoginMode.signIn);
    });
  });

  group('подтверждение почты в сессии', () {
    test(
      'без подтверждения — экран подтверждения, после — регистрация',
      () async {
        final auth = FakeAuthRepository();
        final c = ProviderContainer(
          overrides: [
            authRepositoryProvider.overrideWithValue(auth),
            userRepositoryProvider.overrideWithValue(FakeBackend()),
          ],
        );
        addTearDown(c.dispose);
        c.listen(sessionProvider, (_, _) {});

        await auth.signUp(email: 'a@mail.ru', password: '12345678');
        for (var i = 0; i < 10; i++) {
          await Future<void>.delayed(Duration.zero);
        }
        expect(c.read(sessionProvider), isA<NeedsEmailVerification>());

        auth.confirmEmail('a@mail.ru');
        await auth.reloadUser();
        for (var i = 0; i < 10; i++) {
          await Future<void>.delayed(Duration.zero);
        }
        expect(c.read(sessionProvider), isA<NeedsRegistration>());
      },
    );
  });
}
