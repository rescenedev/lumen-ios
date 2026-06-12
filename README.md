# Lumen for iOS

**넘기다 보면, 사진이 정리돼요.** 사진 앱처럼 부드럽게 넘기고, 핀치로 줌하면서 —
남길 사진은 보관함에, 지울 사진은 위로 쓱, 실수는 ↩ 한 번. 사진도 동영상도 정리하는
완전 무료 네이티브 iOS 앱입니다.

🌐 **소개 페이지**: https://rescenedev.github.io/lumen/lumen-ios/

## 특징

- **제스처가 전부** — 좌우 페이지 스와이프, 화면 가장자리 탭으로 스텝, 핀치 줌(+더블탭),
  위로 올려 삭제 후보, 보관함 버튼으로 'Lumen' 앨범에 보관, ★ 즐겨찾기, ↩ 되돌리기
- **사진 + 동영상** — 길이 배지가 붙은 동영상도 한 흐름으로, 뷰어에서 탭 재생·스크럽
- **수십만 장도 즉시** — 전체를 순회하지 않는 쿼리 기반 로딩, 보이는 셀만 그리는
  네이티브 그리드, 스크롤을 앞지르는 프리페칭
- **비파괴** — 보관은 즉시 'Lumen' 앨범에(앱이 꺼져도 안전), 삭제는 항상 시스템 확인 후,
  실수는 ↩로 즉시 복구, 다음엔 '이어서 정리'로 그 자리부터
- **Apple 생태계 그대로** — 즐겨찾기·앨범 모두 Apple 사진(PhotoKit) 표준 사용
- **한국어 / English** · 광고도 추적도 없이 모든 처리는 기기 안에서

## 빌드 (무료 Apple ID로 내 폰에 설치)

```bash
git clone https://github.com/rescenedev/lumen-ios.git
cd lumen-ios
xcodegen generate        # brew install xcodegen
open LumenIOS.xcodeproj
```

1. Xcode에서 Signing & Capabilities → 본인 Apple ID 팀 선택
2. 아이폰 연결 → `⌘R`
3. 첫 실행 시: 설정 → 일반 → VPN 및 기기 관리 → 개발자 앱 신뢰

요구사항: iOS 17+, Xcode 16+, 사진 라이브러리 접근 권한.
`LumenIOS.xcodeproj/`는 커밋되지 않습니다 — `project.yml`에서 재생성하세요.

## 구조

```
Sources/
  LumenIOSApp.swift      앱 엔트리
  PhotoLibrary.swift     PhotoKit 데이터 레이어 (lazy fetch, 프리워밍, 변경 감지)
  LibraryView.swift      홈 — 정리할 앨범 고르기
  AlbumGalleryView.swift 앨범 갤러리 (사진 그리드)
  PhotoGridView.swift    UICollectionView 그리드 (연속 핀치 줌, 프리페칭)
  OrganizeView.swift     뷰어/정리 — 페이지 스와이프, 핀치 줌, 보관/★/↩, 동영상 재생
  OrganizeSession.swift  정리 결정 + 되돌리기 로직 (순수, 단위 테스트)
  SettingsView.swift     설정 시트 (홈에서 아래로 당겨 호출)
  Shared/ImageEditor.swift  크로스플랫폼 편집 엔진 (macOS 버전과 동일 소스)
AppStore/                App Store 메타데이터·스크린샷 (screenshots/{ko,en-US}/)
```

이 편집 엔진(`Sources/Shared/ImageEditor.swift`)은 macOS [rescenedev/lumen](https://github.com/rescenedev/lumen)과
같은 소스를 공유합니다 — 양쪽에 벤더링되어 있으니 한쪽을 고치면 다른 쪽도 함께 반영하세요.

## 라이선스

MIT — macOS 버전은 [rescenedev/lumen](https://github.com/rescenedev/lumen),
소개 페이지는 [여기](https://rescenedev.github.io/lumen/lumen-ios/).
