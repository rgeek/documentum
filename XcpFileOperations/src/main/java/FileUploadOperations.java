import com.documentum.fc.client.DfSingleDocbaseModule;
import com.documentum.fc.common.DfLogger;
import org.apache.tika.exception.TikaException;
import org.apache.tika.metadata.Metadata;
import org.apache.tika.metadata.Property;
import org.apache.tika.metadata.TikaCoreProperties;
import org.apache.tika.parser.AutoDetectParser;
import org.apache.tika.parser.ParseContext;
import org.xml.sax.SAXException;
import org.xml.sax.helpers.DefaultHandler;

import java.io.FileInputStream;
import java.io.IOException;

public class FileUploadOperations extends DfSingleDocbaseModule {

    public String getDocumentCreationDate(String xCPFileUuid) {

        String fileUuid = xCPFileUuid.replaceFirst("^files/", "");

        System.out.println(fileUuid);

        String generateFilePath = System.getProperty("java.io.tmpdir") + "/"+fileUuid;
        System.out.println(generateFilePath);
        DfLogger.info(this,generateFilePath,null,null);
        return readMetadataFromDocument(generateFilePath, TikaCoreProperties.CREATED);


    }

    public String readMetadataFromDocument(String filePath, Property metadataProperty) {
        Metadata metadata = new Metadata();
        AutoDetectParser parser = new AutoDetectParser();

        try (FileInputStream fis = new FileInputStream(filePath)) {
            try {
                parser.parse(fis, new DefaultHandler(), metadata, new ParseContext());
            } catch (IOException | SAXException | TikaException e) {
                throw new RuntimeException(e);
            }
        } catch (IOException e) {
            throw new RuntimeException(e);
        }

        for (String name : metadata.names()) {
            System.out.println(name + " = " + metadata.get(name));
        }
        System.out.println(filePath + "---" + metadata.get(metadataProperty));
        DfLogger.info(this,filePath + "---" + metadata.get(metadataProperty),null,null);
        return metadata.get(metadataProperty);


    }

}
