# TF2-World-Of-Tanks
  
필수 플러그인
---
[TF2Attributes](https://github.com/FlaminSarge/tf2attributes)  
[TF2Items](https://github.com/asherkin/TF2Items)
  
설치방법
---
1. [릴리즈](https://github.com/Modded-Madness/TF2-World-Of-Tanks/releases/latest)로 이동해 TF2-World-Of-Tanks.zip 파일을 다운로드
2. 해당 파일을 압축풀기 한 다음, TF2 Sourcemod 서버에 덮어 씌움
  
실행 방법
---
1. 맵 시작 전, 다음의 서버에서 다음 커맨드가 자동 실행되도록 설정 <code>sm plugins load world_of_tanks.smx</code>
2. 모드가 바뀔 경우에는 다음의 커맨드가 실행되도록 해서 플러그인을 비활성화 <code>sm plugins unload world_of_tanks.smx</code>


변수
---
sm_soldiertank_enabled 0 - 비활성화, 1 - 활성화 (기본 값 - 1)

주의사항
---
항상 맵이 로드 되기 전, <code>world_of_tanks.smx</code>플러그인이 먼저 로드 되어야 합니다
  
지원하는 맵
---
Team Fortress 2에서 지원하는 모든 공식 맵
(넓은 koth 맵 추천)

변경 이력
---
우클릭으로 발사하는 직격포가 제대로 맞지 않던 문제 수정 (2022-08-06)
