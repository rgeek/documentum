package com.training.dctm.job;

import com.documentum.fc.client.IDfModule;
import com.documentum.fc.client.IDfSession;
import com.documentum.fc.common.DfLogger;
import com.documentum.fc.methodserver.IDfMethod;

import java.io.PrintWriter;
import java.util.Map;

public class AutoLinkClaimDocument implements IDfModule, IDfMethod {


    @Override
    public int execute(Map map, PrintWriter printWriter) throws Exception {
        DfcSessionUtil dfcSessionUtil = null;
        IDfSession dfcSession=null;
        try {
            DfLogger.info(this, "Checking Method Execution", null, null);
            JobDefaultArguments jobDefaultArguments = parseArguments(map);
            dfcSessionUtil = new DfcSessionUtil();
            dfcSession=dfcSessionUtil.getSession(jobDefaultArguments.getUserName(), "", jobDefaultArguments.getDocbaseName());
            DfLogger.info(this, dfcSession.getDBMSName(), null, null);
            //business Logic here
            //doAutoLinking(dfcSession);
        } catch (Exception e) {
            DfLogger.error(this, "Error:{0}", new String[]{e.getMessage()}, e);
            throw new Exception(e);
        } finally {
            if (dfcSession != null) {
                dfcSessionUtil.releaseSession(dfcSession);
            }

        }


        return 0;
    }

    public JobDefaultArguments parseArguments(Map<Object, Object> map) {

        JobDefaultArguments jobDefaultArguments = new JobDefaultArguments();

        for (Map.Entry<Object, Object> entryObj : map.entrySet()) {


            String key = (String) entryObj.getKey();
            String[] value = (String[]) entryObj.getValue();
            DfLogger.info(this, "Key" + key, null, null);
            if (key.equals("user_name")) {
                jobDefaultArguments.setUserName(value[0]);
            }
            if (key.equals("docbase_name")) {
                jobDefaultArguments.setDocbaseName(value[0]);
            }
        }

        return jobDefaultArguments;

    }
}



