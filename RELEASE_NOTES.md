# Extended Pickup Icons Range v2.5

Import the attached mod ZIP into Arsenal. Requires Bingus Shared Loader v15+. Tested on HELLDIVERS 2 Steam build 25480438.

## What's new

- **Survives more game updates.** The mod no longer locks itself to one exact game version. It finds each item by its ID, so small game patches should not break it.
- **Plays nicer with other mods.** If another mod or a game update has changed an item, only that item is skipped. The rest of the mod still works.
- **Options no longer affect each other.** A problem with the stim marker no longer turns off Samples or Equipment.
- **Smoother startup.** The large file check at game start is gone, and the data search is spread over the loading screen.
- **Same icons, same distances.** Nothing changes in what you see compared with 2.4.

After a big game update, check `%LOCALAPPDATA%\CowboyBingus\Helldivers2\Logs\CodexPickupIconRangeTest.log`. `skipped 0 unmatched` means everything applied. A long list of skipped items means that update changed them and the mod needs an update.

## 변경 내용

- **게임 업데이트에 덜 민감해졌습니다.** 특정 게임 버전에 고정하지 않고 아이템을 ID로 찾아서, 작은 업데이트 후에도 계속 작동합니다.
- **다른 모드와 더 잘 어울립니다.** 다른 모드나 업데이트로 달라진 아이템은 그것만 건너뛰고 나머지는 정상 적용합니다.
- **옵션끼리 영향을 주지 않습니다.** 자극제 표시에 문제가 생겨도 Samples와 Equipment는 정상 적용됩니다.
- **시작이 더 부드러워졌습니다.** 게임 시작 때 큰 파일을 검사하던 과정을 없앴습니다.
- **아이콘과 거리는 v2.4와 같습니다.**

**설치:** 게임 종료 → 구버전 비활성화 → Shared Loader 활성화 → 아래 모드 ZIP을 Arsenal에 가져오기 → 옵션 선택 → Purge / Deploy.

GitHub's automatic source-code archives are not installable Arsenal packages.

SHA-256: `286fb044425749e105296d131d1b3d66370d6d1069699d0e6f6088db7eebc32e`
