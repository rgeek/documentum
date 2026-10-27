import com.documentum.fc.common.DfException;
import com.documentum.fc.tools.RegistryPasswordUtils;

public class PassUtils {

    public static void main(String[] args) throws DfException {
        System.out.println(RegistryPasswordUtils.encrypt("Ecmdctmcoe@July2024"));
    }
}
