/**
 * REFUGIO DE CARACOLES — BACKEND + FRONTEND (Google Apps Script)
 *
 * doGet sirve el juego completo (archivo Index.html, una
 * copia de refugio_de_caracolesVask.html) para que se pueda
 * abrir directamente visitando la URL del despliegue, desde
 * cualquier dispositivo, sin necesidad de tener el archivo
 * local.
 *
 * doPost es la API que ese mismo HTML usa (por fetch) para
 * registrar usuarios e ir guardando/cargando el progreso de
 * cada uno como JSON dentro de una carpeta de Google Drive.
 *
 * Cómo se despliega y cómo actualizar el juego después: ver
 * INSTRUCCIONES_DESPLIEGUE.md, en la carpeta del proyecto.
 */

const FOLDER_ID = "1FOQST5mWWZ8zG2I0d5AXFQIZYZUNjUBC";
const USERS_FILE = "usuarios.json";
const PROGRESS_FILE = "progreso.json";


/* =========================================================
   PUNTO DE ENTRADA HTTP
========================================================= */

function doPost(e) {

  var body;

  try {
    body = JSON.parse(e.postData.contents);
  } catch (err) {
    return jsonResponse({ ok: false, error: "Solicitud inválida." });
  }

  var action = body.action;

  var lock = LockService.getScriptLock();
  lock.waitLock(15000);

  try {

    switch (action) {

      case "register":
        return jsonResponse(registerUser(body.username, body.password));

      case "login":
        return jsonResponse(loginUser(body.username, body.password));

      case "load":
        return jsonResponse(loadProgress(body.username, body.password));

      case "save":
        return jsonResponse(saveProgress(body.username, body.password, body.data));

      default:
        return jsonResponse({ ok: false, error: "Acción desconocida: " + action });

    }

  } catch (err) {

    return jsonResponse({ ok: false, error: String(err) });

  } finally {

    lock.releaseLock();

  }

}


function doGet(e) {

  return HtmlService
    .createHtmlOutputFromFile("Index")
    .setTitle("🐌 Refugio de Caracoles ULTRA")
    .addMetaTag("viewport", "width=device-width,initial-scale=1.0");

}


function jsonResponse(obj) {

  return ContentService
    .createTextOutput(JSON.stringify(obj))
    .setMimeType(ContentService.MimeType.JSON);

}


/* =========================================================
   ACCESO A LOS ARCHIVOS EN DRIVE
========================================================= */

function getFolder() {
  return DriveApp.getFolderById(FOLDER_ID);
}


function readJsonFile(name, fallback) {

  var files = getFolder().getFilesByName(name);

  if (!files.hasNext()) {
    return fallback;
  }

  var content = files.next().getBlob().getDataAsString();

  if (!content) {
    return fallback;
  }

  try {
    return JSON.parse(content);
  } catch (err) {
    return fallback;
  }

}


function writeJsonFile(name, data) {

  var folder = getFolder();
  var files = folder.getFilesByName(name);
  var text = JSON.stringify(data, null, 2);

  if (files.hasNext()) {
    files.next().setContent(text);
  } else {
    folder.createFile(name, text, MimeType.PLAIN_TEXT);
  }

}


/* =========================================================
   USUARIOS Y CONTRASEÑAS

   Las contraseñas nunca se guardan en texto plano: se
   guarda un hash SHA-256 con una "sal" (salt) única por
   usuario, generada con Utilities.getUuid().
========================================================= */

function normalizeUsername(username) {
  return String(username || "").trim().toLowerCase();
}


function isValidUsername(username) {
  return /^[a-z0-9_]{3,24}$/.test(username);
}


function hashPassword(password, salt) {

  var raw = Utilities.computeHmacSha256Signature(String(password), String(salt));

  return raw.map(function (byte) {
    var v = (byte < 0 ? byte + 256 : byte).toString(16);
    return v.length === 1 ? "0" + v : v;
  }).join("");

}


function checkPassword(username, password) {

  var users = readJsonFile(USERS_FILE, {});
  var user = users[username];

  if (!user) {
    return false;
  }

  return hashPassword(password, user.salt) === user.hash;

}


/* =========================================================
   REGISTRO
========================================================= */

function registerUser(username, password) {

  username = normalizeUsername(username);

  if (!isValidUsername(username)) {
    return { ok: false, error: "Usuario inválido (3 a 24 letras, números o _)." };
  }

  if (!password || String(password).length < 4) {
    return { ok: false, error: "La contraseña debe tener al menos 4 caracteres." };
  }

  var users = readJsonFile(USERS_FILE, {});

  if (users[username]) {
    return { ok: false, error: "Ese usuario ya existe." };
  }

  var salt = Utilities.getUuid();

  users[username] = {
    salt: salt,
    hash: hashPassword(password, salt),
    createdAt: new Date().toISOString()
  };

  writeJsonFile(USERS_FILE, users);

  var progress = readJsonFile(PROGRESS_FILE, {});
  progress[username] = defaultGameState();
  writeJsonFile(PROGRESS_FILE, progress);

  return { ok: true };

}


/* =========================================================
   INICIO DE SESIÓN
========================================================= */

function loginUser(username, password) {

  username = normalizeUsername(username);

  if (!checkPassword(username, password)) {
    return { ok: false, error: "Usuario o contraseña incorrectos." };
  }

  var progress = readJsonFile(PROGRESS_FILE, {});

  return {
    ok: true,
    data: progress[username] || defaultGameState()
  };

}


/* =========================================================
   CARGAR PROGRESO
========================================================= */

function loadProgress(username, password) {

  username = normalizeUsername(username);

  if (!checkPassword(username, password)) {
    return { ok: false, error: "Usuario o contraseña incorrectos." };
  }

  var progress = readJsonFile(PROGRESS_FILE, {});

  return {
    ok: true,
    data: progress[username] || defaultGameState()
  };

}


/* =========================================================
   GUARDAR PROGRESO
========================================================= */

function saveProgress(username, password, data) {

  username = normalizeUsername(username);

  if (!checkPassword(username, password)) {
    return { ok: false, error: "Usuario o contraseña incorrectos." };
  }

  var progress = readJsonFile(PROGRESS_FILE, {});
  progress[username] = data;
  writeJsonFile(PROGRESS_FILE, progress);

  return { ok: true };

}


/* =========================================================
   ESTADO INICIAL POR DEFECTO
========================================================= */

function defaultGameState() {

  return {
    coins: 300,
    snails: [],
    eggs: [],
    envelopes: [],
    nursery: [],
    discovered: [],
    foods: [],
    night: false,
    seconds: 0,
    feed: 0,
    pet: 0,
    daily: false,
    highScores: { food: 0, star: 0, snake: 0 }
  };

}
