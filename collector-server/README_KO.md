# WoWQuestVoice 익명 퀘스트 수집 서버

Cloudflare Workers가 HTTPS 요청을 받고 D1이 중복을 제거해 저장합니다.

수집 항목은 퀘스트 ID, 구간(수락/진행/완료), 제목, 본문, `koKR`, 클라이언트 빌드와 애드온 버전뿐입니다. 계정명, 캐릭터명, 서버명과 SavedVariables 경로는 보내지 않습니다.

## 배포 순서

1. `npm install`
2. `npx wrangler login`
3. `npx wrangler d1 create wowquestvoice-collector --location apac`
4. 출력된 `database_id`를 Wrangler 설정에 넣습니다.
5. `npm run db:remote`
6. `npx wrangler secret put ABUSE_SALT` (충분히 긴 무작위 값)
7. `npx wrangler secret put UPLOAD_TOKEN` (이전 비공개 클라이언트 호환용, 선택)
8. `npx wrangler secret put ADMIN_TOKEN`
9. `npm run deploy`

사용자 자동 전송기는 명시적인 한 번의 동의 후에만 활성화합니다. 활성화 뒤에는 WoW가 `/reload` 또는 로그아웃으로 SavedVariables를 디스크에 저장할 때 새 문장만 자동 전송합니다.

공개 설치 프로그램에는 수집 비밀값을 넣지 않습니다. 서버는 접속 주소를 날짜별 HMAC으로 익명화한 뒤 전송 횟수와 레코드 수를 제한하며, 원본 주소를 D1에 저장하지 않습니다.
