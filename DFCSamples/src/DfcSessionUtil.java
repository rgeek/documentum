import com.documentum.com.DfClientX;
import com.documentum.com.IDfClientX;
import com.documentum.fc.client.*;
import com.documentum.fc.common.DfException;
import com.documentum.fc.common.DfLoginInfo;
import com.documentum.fc.common.IDfLoginInfo;

import java.io.IOException;


public class DfcSessionUtil {

    public IDfSession getSession(String userName, String password, String docbase) throws DfException, IOException {
        IDfSession dfSession=null;
        IDfClientX clientX=new DfClientX();
        IDfClient client=clientX.getLocalClient();
        IDfLoginInfo loginInfo=new DfLoginInfo();
        loginInfo.setUser(userName);
        loginInfo.setPassword(password);
        IDfSessionManager sessionManager= client.newSessionManager();
        sessionManager.setIdentity(docbase,loginInfo);

        dfSession=sessionManager.getSession(docbase);
        System.out.println("Session Received");
        return dfSession;
    }

    public void releaseSession(IDfSession session){
        if(session!=null){
            System.out.println("Session Released");
            IDfSessionManager sessionManager= session.getSessionManager();
            sessionManager.release(session);
        }

    }
}
