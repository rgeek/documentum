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
%><%
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
~ © Copyright 2022 OpenText Corp. All rights reserved.
-->
<html lang="<%=clientLocale.getLanguage()%>">
<head>
    <meta http-equiv="Content-Type" content="text/html; charset=utf-8" />
	<meta http-equiv="X-UA-Compatible" content="IE=edge" />
    <meta http-equiv="Cache-Control" content="no-cache" />
    <meta name="viewport" content="width=device-width, initial-scale=1, maximum-scale=10, user-scalable=yes">
    <link rel="stylesheet" type="text/css" href="component/xcp-core/xcp_signin/contents-${applicationVersion}.css"/>
    <script type="text/javascript" src="${resourceUrl}/js/ext/ext-all<%= rtl ? "-rtl" : "" %><%= nominify ? "-debug" : "" %>.js"></script>
    <script type="text/javascript" src="${resourceUrl}/js/ext/locale/locale-<%=extLangFileSuffix%><%= nominify ? "-debug" : "" %>.js"></script>
    <script type="text/javascript" src="${resourceUrl}/js/AppConfiguration.js"></script>
    <script type="text/javascript">
        document.title = xcp.appContext.name;
        xcp.appContext.version = '${applicationVersion}';
        xcp.componentVersion = '${applicationVersion}';
        xcp.extLangFileSuffix = "<%=extLangFileSuffix%>";
        xcp.language = "<%=lang%>";
        rtl = "<%=rtl%>";

        try {
            history.go(+1);
        } catch (Error) {
            //Ignore
        }

        Ext.onReady(function() {
            Ext.USE_NATIVE_JSON = false;
            Ext.Boot.config.disableCaching = false;
            Ext.Loader.config.disableCaching = false;
            function loadSignInPageJson() {
                Ext.Ajax.request({
                    url: "ui/pages/application/signin?lang=" + xcp.language,
                    async: false,
                    disableCaching : false,
                    success: function(response, options) {
                        var signInPanelConfig = Ext.JSON.decode(response.responseText);
                        if (rtl) {
                            Ext.apply(signInPanelConfig, {rtl: true});
                        }
                        var signInPanel = Ext.ComponentMgr.create(signInPanelConfig);
                        signInPanel.render("signin-area");
                        xcp.util.SignInUtil.initUI(signInPanel);
                    },
                    failure: function(response, options) {
                        throw "Error while retrieving Sign In dialog.";
                    }
                });
            }

            Ext.Loader.loadScript({
                url: [
                    'component/xcp-core/xcp_signin/contents-${applicationVersion}.js?locale=<%=lang%><%= nominify ? "&nominify=true" : "" %><%= automation ? "&automation=true" : "" %>',
                    'component/xcp-core/xcp_theme_lib/contents-${applicationVersion}.js?locale=<%=lang%><%= nominify ? "&nominify=true" : "" %><%= automation ? "&automation=true" : "" %>'
                ],
                onLoad: function () {
                    Ext.Function.defer(function () {
                        //load default and custom theme
                        xcp.core.ThemeManager.initThemes(<%=nominify%>, <%=rtl%>);
                        xcp.core.ThemeManager.loadApplicationTheme(loadSignInPageJson);
                    }, 1);
                }
            });
        });
    </script>
</head>
<body id="signin-page" <%= rtl ? "style=\"direction:rtl\"" : "" %>>
<div id="msg-area" class="msg-area-div <%= rtl ? "x-rtl" : "" %>"></div>
<form method="post">
    <div id="signin-area" class="signin-area-div"></div>
</form>
</body>
</html>
<% } %>