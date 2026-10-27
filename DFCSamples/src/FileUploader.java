import com.documentum.fc.client.IDfDocument;
import com.documentum.fc.client.IDfSession;
import com.documentum.fc.client.IDfSysObject;
import com.documentum.fc.common.DfException;

import java.io.*;
import java.net.UnknownHostException;

public class FileUploader{
    public static void main(String args[]) throws DfException, IOException {

        DfcSessionUtil sessionUtil=new DfcSessionUtil();
       String filePath=args[0];
        Integer fileCount=Integer.valueOf(args[1]);


        IDfSession dfcSession=sessionUtil.getSession("dmadmin","Ecmdctmcoe@July2024","ecmdev_db");

        System.out.println(dfcSession.getDBMSName());
        for(int i=0;i<fileCount;i++){
            IDfSysObject documentObject=(IDfSysObject) dfcSession.newObject("tro_claim_document");
            documentObject.setString("cd_status","Draft");
            documentObject.setObjectName("FileFromUtil_"+i+"_file.pdf");
            documentObject.setContentType("pdf");
            documentObject.setContent(getByteArray(filePath));
            documentObject.link("/TrainingOffshore/1596806468");
            documentObject.save();
        }

        sessionUtil.releaseSession(dfcSession);


    }

    public static ByteArrayOutputStream getByteArray(String filePath) throws FileNotFoundException {


            ByteArrayOutputStream baos = new ByteArrayOutputStream();

            try (FileInputStream fis = new FileInputStream(filePath)) {
                byte[] buffer = new byte[8192];
                int bytesRead;

                while ((bytesRead = fis.read(buffer)) != -1) {
                    baos.write(buffer, 0, bytesRead);
                }
            } catch (IOException e) {
                throw new RuntimeException(e);
            }

        return baos;

    }
}

