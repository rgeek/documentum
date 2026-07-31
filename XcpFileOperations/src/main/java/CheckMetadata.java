import org.apache.tika.metadata.TikaCoreProperties;

public class CheckMetadata {

    public static void main(String[] args) {
        FileUploadOperations fileUploadOperations =new FileUploadOperations();
        fileUploadOperations.readMetadataFromDocument("C:\\Users\\Rahul.Narula\\OneDrive - Coforge Limited\\Documents\\DCTM-244\\Composer24.4Guide.pdf", TikaCoreProperties.CREATED);
    }
}
