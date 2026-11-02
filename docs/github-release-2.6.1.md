Improves resupply-crate icon rendering and fading, reduces repeated drawing/unit-query work, and preserves important markers when the 40-marker limit is reached. **Settings saved in 2.6.0 are preserved.**

Changes from **2.6.0**:

- Render the resupply-crate icon as a texture using the same source artwork.
- Reduce repeated discovery, position, code/keycard mesh and damaged-Hellbomb geometry queries.
- Avoid unnecessary repeated vehicle/weapon/wreck discovery for confirmed destroyed vehicles.
- Prioritize the last death marker, then vehicles/Hellbombs, then the nearest remaining targets.
- Use Chef-managed support logging (`ExtendedPickupIcons.log`) and avoid blocked old-log reads.
- Fix resolution fallback when the game's `Gui` table is missing.
- Preserve per-frame local death confirmation, the eight-frame full discovery bound, existing targets and settings.

Requires **Chef Shared Loader 1.4.0+**; latest recommended. Remove the previous mod version before installing. Only upgrades from versions older than 2.6.0 start with default settings.

**Validation:** 231 automated tests passed. Resupply fading, vehicle-death placement and vehicle destruction were confirmed in gameplay. The released Lua matches tested `2.6.1-test.2` except for the version string; texture data is unchanged from that build. Lower simulated API call counts are not an FPS measurement.

---

재보급 상자 아이콘·흐림 표시를 개선하고 반복 렌더링·유닛 조회 부담을 줄였습니다. 마커 40개 제한에 도달하면 중요한 마커를 우선 남깁니다. **이미 저장한 2.6.0 설정은 유지됩니다.**

직전 공개 버전 **2.6.0 대비 변경**:

- 같은 원본 이미지를 사용하는 텍스처로 재보급 상자 아이콘을 렌더링합니다.
- 반복 탐색·위치 조회와 발사 코드·키카드의 메시 확인, 불발 헬밤의 모델 확인 횟수를 줄였습니다.
- 파괴가 확정된 차량의 차량·무장·잔해 반복 탐색을 줄였습니다.
- 마지막 사망 위치, 차량·헬밤, 나머지 가까운 대상 순으로 마커를 남깁니다.
- Chef 공식 로그 관리와 `ExtendedPickupIcons.log`를 사용하고 차단되는 이전 로그 읽기를 제거했습니다.
- `Gui` 테이블이 없을 때 화면 크기 대체 처리가 실패하던 문제를 수정했습니다.
- 매 프레임 수행하는 내 사망 확인, 전체 탐색 8프레임 이내 주기, 기존 표시 대상과 설정을 유지합니다.

**Chef Shared Loader 1.4.0 이상**이 필요하며 최신 버전을 권장합니다. 이전 모드 버전을 제거한 뒤 설치하세요. 2.6.0보다 오래된 버전에서 업데이트할 때만 설정이 기본값으로 시작합니다.

**검증:** 자동 테스트 231개 통과. 재보급 흐림, 차량 내 사망 위치와 차량 파괴 처리는 실게임에서 확인했습니다. 정식 Lua는 테스트한 `2.6.1-test.2`와 버전 문자열만 다르며 텍스처 데이터도 같습니다. 모의 API 호출량 감소는 FPS 측정 결과가 아닙니다.
