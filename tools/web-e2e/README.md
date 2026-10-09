# Web end-to-end runs

Real-browser checks of the deployed or locally served Next.js site and of the Flutter web
build, against the live Firebase project. They need credentials in the environment and
never store them:

    export MYS_TEST_EMAIL=...  MYS_TEST_PASSWORD=...
    npm install && npx playwright install chromium

    # serve the Next.js static export the way Firebase Hosting does, then run
    node server.mjs "<path to next app>/out" 4173 &
    node e2e.mjs http://localhost:4173 local          # boards, completion, flows, routes, responsive
    node e2e_recurrence.mjs http://localhost:4173     # repeat completion checked in the database
    node e2e_delete.mjs http://localhost:4173         # account deletion with a throwaway account

    # Flutter web release build
    node server_spa.mjs build/web 4180 &
    node flutter_web.mjs http://localhost:4180

`cleanup_e2e.mjs` removes anything a run left in the shared test account. The deletion run
creates and deletes its own throwaway account and never touches the shared one.
