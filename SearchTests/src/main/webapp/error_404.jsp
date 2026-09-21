<%@ page contentType="text/html;charset=UTF-8" language="java" %>
<html>
<head>
  <title>Page not found</title>
  <style>
    html, body {
      height: 100%;
      margin: 0;
      padding: 0;
      border: 0;
    }
    #wrap {
      position: relative;
      width: 100%;
      height: 100%;
      margin: 0;
    }
    #content {
      position: absolute;
      top: 50%;
      left: 50%;
      height: 220px;
      width: 700px;
      margin: -110px 0 0 -350px;
      background-color: #eee;
      border: 1px solid #d7d7d7;
      border-radius: 3px;
      box-shadow: rgba(0, 0, 0, 0.2) 0 0 3px 1px;
    }
    #logo {
      display: block;
      margin: 30px auto 0 auto;
    }
    #msg {
      color: #449;
      font-family: Tahoma, Verdana, sans-serif;
      font-size: 1.5em;
      text-align: center;
      margin: 40px;
    }
  </style>
  <script type="text/javascript">
      function setImageSrc() {
          var img = document.getElementById('logo');
          var loc = location.pathname;
          img.src = loc.substring(0, loc.indexOf('/', 1)) + '/icons/welcome.png';
      }
  </script>
</head>
<body onload="setImageSrc()">
<div id="wrap">
  <div id="content">
    <div>
      <img id="logo"/>
      <div id="msg">The page you requested was not found on the server</div>
    </div>
  </div>
</div>
</body>
</html>
