<%!
    /*
     * Ensure there is no output (not even whitespace) till the if condition for validParams check
     */
    private static final String NOMINIFY = "nominify";
    private static final String AUTOMATION = "automation";

    private Boolean getBooleanParam(ServletRequest req, String param, boolean defaultValue) {
        param = req.getParameter(param);
        if ("".equals(param)) {
            return defaultValue;
        }
        if (param != null && !"true".equals(param) && !"false".equals(param)) {
            return null;
        } else {
            return Boolean.valueOf(param);
        }
    }

    // ExtJs has some language packs specific to country, below is the list of it.
    private static final Set extCountryLangPacks = new TreeSet();
    static {
        extCountryLangPacks.add("zh_TW");
        extCountryLangPacks.add("zh_CN");
        extCountryLangPacks.add("sv_SE");
        extCountryLangPacks.add("sr_RS");
        extCountryLangPacks.add("pt_PT");
        extCountryLangPacks.add("pt_BR");
        extCountryLangPacks.add("no_NN");
        extCountryLangPacks.add("no_NB");
        extCountryLangPacks.add("fr_CA");
        extCountryLangPacks.add("en_GB");
        extCountryLangPacks.add("en_AU");
        extCountryLangPacks.add("el_GR");
    };
%>

<%
    boolean validParams = true;

    Boolean nominify = getBooleanParam(request, NOMINIFY, true);
    if (nominify == null) {
        validParams = false;
    }

    Boolean automation = getBooleanParam(request, AUTOMATION, true);
    if (automation == null) {
        validParams = false;
    }

    if (!validParams) {
        response.setStatus(HttpServletResponse.SC_BAD_REQUEST);
        response.getWriter().println("Invalid request parameters");
    } else {
        Locale clientLocale = request.getLocale();
        String lang = clientLocale.getLanguage();
        String country = clientLocale.getCountry();
        String extLangFileSuffix = lang;

        if (country != null && country.length() > 0) {
            String str = lang + "_" + country;
            lang = lang + "_" + country;
            if (extCountryLangPacks.contains(str)) {
                extLangFileSuffix = str;
            }
        }

        boolean rtl = false;
        ComponentOrientation orientation = ComponentOrientation.getOrientation(clientLocale);
        if (!orientation.isLeftToRight()) {
            rtl = true;
        }
%>

<%@ taglib prefix="spring" uri="http://www.springframework.org/tags" %>
<%@ page session="false" %>
<%@ page import="java.util.*" %>
<%@ page import="java.awt.ComponentOrientation" %>
<%@ page contentType="text/html;charset=UTF-8" %>

<spring:eval expression="@applicationInfo['version']" var="applicationVersion"/>
<spring:url value="/resources/{applicationVersion}" var="resourceUrl">
    <spring:param name="applicationVersion" value="${applicationVersion}"/>
</spring:url>

<!DOCTYPE html>

<!--
~ © Copyright 2019 OpenText Corp. All rights reserved.
-->

<html lang="<%=clientLocale.getLanguage()%>">
<head>
    <meta charset="UTF-8">
	<meta http-equiv="X-UA-Compatible" content="IE=edge">
    <title>OTDS redirect</title>
	<script type="text/javascript" src="${resourceUrl}/js/ext/ext-all<%= rtl ? "-rtl" : "" %><%= nominify ? "-debug" : "" %>.js"></script>
    <script type="text/javascript" src="${resourceUrl}/js/ext/locale/locale-<%=extLangFileSuffix%><%= nominify ? "-debug" : "" %>.js"></script>
	<script type="text/javascript">
		
		const LOOP_WINDOW_MS   = 10_000;   // 10 seconds
        const REDIRECT_TS      = 'otds_redirect_ts';
		
		Ext.onReady(function() {
			Ext.USE_NATIVE_JSON = false;
			Ext.Boot.config.disableCaching = false;
			Ext.Loader.config.disableCaching = false;
			Ext.Loader.loadScript({
				url: [
					'component/xcp-core/xcp_signin/contents-${applicationVersion}.js?locale=<%=lang%><%= nominify ? "&nominify=true" : "" %><%= automation ? "&automation=true" : "" %>'
				],
				onLoad: function () {
					Ext.Function.defer(function () {							
						var strings = xcp.Strings.util.SignInUtil;
						otdsredirect(strings);
					}, 1);
				}
			});
		});
		
		function otdsredirect(strings) {
			
			let lastRedirect = getCookie(REDIRECT_TS);

			if (lastRedirect) {
            let lastRedirectTime = parseInt(lastRedirect, 10);
            let now = Date.now();

                if ((now - lastRedirectTime) < LOOP_WINDOW_MS) {
          		document.getElementById('appmessage').innerHTML = strings.ssoAuthenticationFailed;	
                return; 
				}
			}

      
        setCookie(REDIRECT_TS, Date.now(), 60); // cookie lasts 60 sec (can adjust)
			
			var islogout = getQueryParam(window.location.search.substr(1), 'logout');
			if(islogout) {
				writeCookie('otds_access_token', null);
				writeCookie('otds_username', null);
				document.getElementById('appmessage').innerHTML = strings.ssoSessionClosed;
				return;
			}
			// refer oauth2-client.js
			let _state = getQueryParam(window.location.hash.substr(1), 'state');
			let stateObj = JSON.parse(window.localStorage.getItem(_state));
			if (stateObj) {
			  if (new Date(stateObj['exp']).getTime() > new Date().getTime()) {
				if (
				  stateObj['login-type'] == 'iframe' ||
				  stateObj['login-type'] == 'popup-window'
				) {
				  let _token = getQueryParam(
					window.location.hash.substr(1),
					'access_token'
				  );
				  if (_token) {
					_token = removeNewLineChars(_token);
					if (stateObj['login-type'] == 'iframe') {
					  window.top.postMessage({
						data: {
						  token: _token,
						  loginType: stateObj['login-type'],
						  state: _state,
						},
						error: null,
					  });
					}
					if (stateObj['login-type'] == 'popup-window') {
					  window.opener.postMessage({
						data: {
						  token: _token,
						  loginType: stateObj['login-type'],
						  state: _state,
						},
						error: null,
					  });
					  window.close();
					}
				  } else {
					let error = getQueryParam(
					  window.location.hash.substr(1),
					  'error_description'
					);
					if (!error) {
					  error = 'Failed to fetch access token for unknown reason';
					}
					if (stateObj['login-type'] == 'iframe') {
					  window.top.postMessage({
						data: {
						  token: null,
						  loginType: stateObj['login-type'],
						  state: _state,
						},
						error: error,
					  });
					}
					if (stateObj['login-type'] == 'popup-window') {
					  window.opener.postMessage({
						data: {
						  token: null,
						  loginType: stateObj['login-type'],
						  state: _state,
						},
						error: error,
					  });
					  window.close();
					}
				  }
				}
			  } else {
				// time expired
				if (stateObj['login-type'] == 'iframe') {
				  window.top.postMessage({
					data: { token: null, loginType: stateObj['login-type'], state: _state },
					error: 'state value expired',
				  });
				}
				if (stateObj['login-type'] == 'popup-window') {
				  window.opener.postMessage({
					data: { token: null, loginType: stateObj['login-type'], state: _state },
					error: 'state value expired',
				  });
				  window.close();
				}
			  }
			  return;
			}
            var access_token = removeNewLineChars(getQueryParam(window.location.hash.substr(1), 'access_token'));
			
            if(access_token){
				var state = getQueryParam(window.location.hash.substr(1), "state");
				var orguri = getDecodeduri(state);
				
				document.getElementById('appmessage').innerHTML = strings.ssoAuthenticatingToken;
				
                if(!orguri) {
                    orguri = getAppurl();
				}
				
                authenticateAccessToken(orguri, access_token, strings);                
            }
        }
		
		function getAppContextPath() {
			var pathname = window.location.pathname;
			return pathname.substr(0, pathname.lastIndexOf('/'));
		}
		
        function getAppurl(){            
            return window.location.origin + getAppContextPath();
        }
		
		function getQueryParam(querystr, paraname){
            var otdsquerystr = querystr;
            var otdsparamarray = new Array();
            otdsparamarray = otdsquerystr.split('&');
            var otdstemppara = null;
            for(i=0;i<otdsparamarray.length;i++){
                otdstemppara = otdsparamarray[i];
                if(otdstemppara.indexOf(paraname) != -1){
                    return otdstemppara.substring(otdstemppara.indexOf('=') + 1);
                }
            }
        }
		
		function authenticateAccessToken(appurl, access_token, strings){
			var jwt_token = parseJwt(access_token);
						
            var xmlHttp = new XMLHttpRequest();			
			xmlHttp.onreadystatechange = function() {
				if(this.readyState == 4) {
					if(this.status == 200){
						document.getElementById('appmessage').innerHTML = strings.ssoAuthenticationSuccessRedirecting;
						writeCookie('otds_username', jwt_token['uid']);
						writeCookie('otds_access_token', access_token);
						window.location = appurl;
					}
					else if(this.status == 401) {
						document.getElementById('appmessage').innerHTML = strings.ssoAuthenticationFailed;					
					}
					else {
						document.getElementById('appmessage').innerHTML = strings.ssoAuthenticationServerError;
					}
				}
			};
			
			xmlHttp.open("GET", appurl, true);
			xmlHttp.setRequestHeader('Authorization', 'bearer ' + access_token);
                        
            xmlHttp.send(null);
        }
		
		function getDecodeduri(orguri){
            return window.atob(decodeURIComponent(orguri));
        }
				
		function parseJwt (token) {
            var base64Url = token.split('.')[1];
            var base64 = base64Url.replace(/-/g, '+').replace(/_/g, '/');
            return JSON.parse(window.atob(base64));
        }
		
		function removeNewLineChars(value) {
			return value.replace(/\\n/g, '').replace(/\\r/g, '').replace(/\\t/g, '').replace(/%0a/g, '').replace(/%0d/g, '');
		}
		
		function writeCookie(name, value) {
			if(null == value) {
				document.cookie = name + '=; path=' + getAppContextPath();
				return;
			}

			//prevent header split attack
			value = removeNewLineChars(value);
			
			document.cookie = name + '=' + value + '; path=' + getAppContextPath();
		}
		
		function setCookie(name, value, maxAge) {
		document.cookie = name + "=" + value + "; Max-Age=" + maxAge + "; Path=" + getAppContextPath() + "; SameSite=Strict; Secure";
		}
		
		function getCookie(name) {
				const m = document.cookie.match(new RegExp('(?:^|; )' + name + '=([^;]*)'));
				return m ? decodeURIComponent(m[1]) : null;
		}
		
		function clearCookie(name) { 
		setCookie(name, '', 0); 
		}
		
    </script>
</head>
<body>
<div align="center" style="font-size:20px" id="appmessage"></div>
</body>
</html>
<% } %>
