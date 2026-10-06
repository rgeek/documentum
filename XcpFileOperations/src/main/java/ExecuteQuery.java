import com.documentum.fc.client.IDfSession;
import com.documentum.fc.common.DfLogger;

public class ExecuteQuery {

    public static void main(String[] args) throws Exception {

       DfLogger.info(ExecuteQuery.class.getName(),"-----Inside XQuery-----",null,null);
        XQueryImpl xQuery = new XQueryImpl();
        String userName = "";
        String password = "";
        String docbase="";
        GetDocumentumSession getDocumentumSession= new GetDocumentumSession();
        //getDocumentumSession.getSession(docbase,userName,password);

        DfLogger.info(ExecuteQuery.class.getName(),"-----Getting XQuery session-----",null,null);
        IDfSession session=getDocumentumSession.getSession(docbase,userName,password);
        DfLogger.info(ExecuteQuery.class.getName(),"-----Executing XQuery-----",null,null);
        xQuery.executeXQuery(session);

    }
}