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

//新規登録処理
$('#newuser').on('click', function() {
  var email = $('#email').value;
  var password = $('#password').value;
  firebase.auth().createUserWithEmailAndPassword(email, password)
  .catch(function(error) {
    alert('登録できません（' + error.message + '）');
  });
});



//ログイン処理
$('#login').on('click', function() {
  var email = $('#email').text();
  var password = $('#password').text();
  firebase.auth().signInWithEmailAndPassword(email, password)
  .catch(function(error) {
    alert('ログインできません（' + error.message + '）');
  });
});



//ログアウト処理
$('#logout').on('click', function() {
  firebase.auth().signOut();
});



//認証状態の確認
firebase.auth().onAuthStateChanged(function(user) {
  if(user) {
    var userID = (user.email).split('@')
    $('#coment3').text(userID[0]);
    loginDisplay();
  }
  else {
    logoutDisplay();
  }
});



function loginDisplay() {
  $('#input-area').classList.add('hide');
  $('#tcard-area').classList.remove('hide');
  $('#email').text("");
  $('#password').text("");
}


function logoutDisplay() {
  $('#input-area').classList.remove('hide');
  $('#tcard-area').classList.add('hide');
  $('#coment').text("");
  $('#coment2').text("");
}

//ロード画面
$(function() {
  var h = $(window).height();
  
  $('#wrap').css('display','none');
  $('#loader-bg ,#loader').height(h).css('display','block');
});
  
$(window).load(function () { //全ての読み込みが完了したら実行
　window.scrollTo(0,0);
  $('#loader-bg').delay(900).fadeOut(800);
  $('#loader').delay(600).fadeOut(300);
  $('#wrap').css('display', 'block');
});
  
//10秒たったら強制的にロード画面を非表示
$(function(){
  setTimeout('stopload()',10000);
});
  
function stopload(){
  $('#wrap').css('display','block');
  $('#loader-bg').delay(900).fadeOut(800);
  $('#loader').delay(600).fadeOut(300);
}

//時刻表示
$(function(){
	setInterval(function(){
		var now = new Date();
		var y = now.getFullYear();
		var m = now.getMonth() + 1;
		var d = now.getDate();
		var w = now.getDay();
		var wd = ['日', '月', '火', '水', '木', '金', '土'];
		var h = now.getHours();
		var mi = now.getMinutes();
		var s = now.getSeconds();
		var mm = ('0' + m).slice(-2);
		var dd = ('0' + d).slice(-2);
		var hh = ('0' + h).slice(-2);
		var mmi = ('0' + mi).slice(-2);
		var ss = ('0' + s).slice(-2);
	$('#hizuke').text(y + '年' + mm + '月' + dd + '日' + '(' + wd[w] + ')');
	$('#hi_fs').css("font-size","200%");
	$('#ji_fs').css("font-size","600%");
	$('#hours').text(hh);
	$('#minutes').text(mmi);
	$('#flash').text(":").fadeOut(1000).fadeIn(1000);
	}, 1000);
});

//位置表示
$(function(){
  function successFunc(position) {
    // 現在位置取得 成功時の処理
    var t = new Date(position.timestamp);
    var _h = t.getHours();
    var _mi = t.getMinutes();
    var _hh = ('0' + _h).slice(-2);
    var _mmi = ('0' + _mi).slice(-2);	  
    $('#coment').text($('#coment').text() + _hh + ":" + _mmi);
	  
　　const url = "https://mreversegeocoder.gsi.go.jp/reverse-geocoder/LonLatToAddress?lat=" + position.coords.latitude + "&lon=" + position.coords.longitude;
    
    $.getJSON(url, function(data) {
	    var addressData = GSI.MUNI_ARRAY[data.results.muniCd];
	    var addressData = addressData.split(',');
	    $('#coment2').text(addressData[1]+ "  " + addressData[3] + "  " + data.results.lv01Nm);
    });
  }

  function errorFunc(error) {
    // 現在位置取得 失敗時の処理
    var errorMessage = {
      0: "現在位置を取得できませんでした。" ,
      1: "位置情報の使用が許可されていません。" ,
      2: "現在位置の取得に失敗しました。" ,
      3: "位置情報の取得がタイムアウトしました。" ,
    };
    var t = new Date();
    var _h = t.getHours();
    var _mi = t.getMinutes();
    var _hh = ('0' + _h).slice(-2);
    var _mmi = ('0' + _mi).slice(-2);	  
    $('#coment').text($('#coment').text() + _hh + ":" + _mmi);
    $('#coment2').text(errorMessage[error.code]);
  }

  // 現在位置取得 オプション
  let options = {
    enableHighAccuracy: true
  }

  $('.btn-circle-border-simple').on('click', function() {
	if($(this).attr('id')=="skin"){
		$('#coment').text("出勤 ");
	}else{
		$('#coment').text("退勤 ");
	}
	  
	if (navigator.geolocation) {
      		navigator.geolocation.getCurrentPosition( successFunc , errorFunc , options ) ;
    	} else { // 現在位置を取得できない場合の処理
      		$('#coment').text("ブラウザは位置検索に対応していません。");
    	}
  });
});
