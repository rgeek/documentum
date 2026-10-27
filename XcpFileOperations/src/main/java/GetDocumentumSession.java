import com.documentum.com.DfClientX;

import com.documentum.fc.client.IDfClient;
import com.documentum.fc.client.IDfSession;
import com.documentum.fc.client.IDfSessionManager;
import com.documentum.fc.common.IDfLoginInfo;
import com.documentum.fc.common.DfLogger;

public class GetDocumentumSession {

    public static IDfSessionManager getSessionManager(String userName, String password) throws Exception {

        DfClientX clientX = new DfClientX();
        IDfClient client = clientX.getLocalClient();

        IDfSessionManager sessionMgr = client.newSessionManager();

        IDfLoginInfo loginInfo = clientX.getLoginInfo();
        DfLogger.info(GetDocumentumSession.class.getName(),"----Validating User----",null,null);

        loginInfo.setUser(userName);
        loginInfo.setPassword(password);

        sessionMgr.setIdentity(IDfSessionManager.ALL_DOCBASES, loginInfo);
        DfLogger.info(GetDocumentumSession.class.getName(),"----SessionManager returned  Successfully----",null,null);
        return sessionMgr;
    }

    public static IDfSession getSession(String userName, String password, String docbaseName) throws Exception {

        IDfSessionManager sessionMgr = getSessionManager(userName, password);
        DfLogger.info(GetDocumentumSession.class.getName(),"----Session returned  Successfully----",null,null);

        return sessionMgr.getSession(docbaseName);
    }
}