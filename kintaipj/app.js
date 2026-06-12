//Firebase初期設定
  var firebaseConfig = {
    apiKey: "AIzaSyA8zeue6O4l9SlXr_LM43Qa73szgsHV44Q",
    authDomain: "model-palace-277910.firebaseapp.com",
    databaseURL: "https://model-palace-277910.firebaseio.com",
    projectId: "model-palace-277910",
    storageBucket: "model-palace-277910.appspot.com",
    messagingSenderId: "981845155739",
    appId: "1:981845155739:web:2e21aae1b758fbfbd0cb3e"
  };
  // Initialize Firebase
  firebase.initializeApp(firebaseConfig);

//DOM取得
var inputarea = document.getElementById('input-area');
var newuser = document.getElementById('newuser');
var login = document.getElementById('login');
var logout = document.getElementById('logout');
var info = document.getElementById('info');



//新規登録処理
newuser.addEventListener('click', function(e) {
  var email = document.getElementById('email').value;
  var password = document.getElementById('password').value;
  
  firebase.auth().createUserWithEmailAndPassword(email, password)
  .catch(function(error) {
    alert('登録できません（' + error.message + '）');
  });
});



//ログイン処理
login.addEventListener('click', function(e) {
  var email = document.getElementById('email').value;
  var password = document.getElementById('password').value;
  
  firebase.auth().signInWithEmailAndPassword(email, password)
  .catch(function(error) {
    alert('ログインできません（' + error.message + '）');
  });
});



//ログアウト処理
logout.addEventListener('click', function() {
  firebase.auth().signOut();
});



//認証状態の確認
firebase.auth().onAuthStateChanged(function(user) {
  if(user) {
    loginDisplay();
  }
  else {
    logoutDisplay();
  }
});



function loginDisplay() {
  logout.classList.remove('hide');
  inputarea.classList.add('hide');

  info.textContent = "ログイン中です！";
}


function logoutDisplay() {
  logout.classList.add('hide');
  inputarea.classList.remove('hide');

  info.textContent = "";
}
