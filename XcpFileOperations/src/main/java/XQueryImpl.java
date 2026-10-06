import java.io.BufferedReader;
import java.io.InputStream;
import java.io.InputStreamReader;

import com.documentum.com.DfClientX;
import com.documentum.com.IDfClientX;
import com.documentum.fc.client.DfSingleDocbaseModule;
import com.documentum.fc.client.IDfSession;
import com.documentum.fc.common.DfException;
import com.documentum.fc.common.DfLogger;
import com.documentum.xml.xquery.IDfXQuery;
import com.documentum.xml.xquery.IDfXQueryTargets;

public class XQueryImpl extends DfSingleDocbaseModule {


    public void executeXQuery(IDfSession session) throws DfException {

        IDfClientX clientX = new DfClientX();
        IDfXQuery xquery = clientX.getXQuery();
        try {
            DfLogger.info(this, "--------Rendering Query------", null, null);
            String query = "declare option xhive:fts-analyzer-class 'com.emc.documentum.core.fulltext.indexserver.core.index.xhive.IndexServerAnalyzer'; declare option xhive:ignore-empty-fulltext-clauses 'true'; let $libs := collection('/ecmdev_db/dsearch/Data') for $dm_doc score $s in $libs/dmftdoc where $dm_doc/dmftmetadata//a_is_hidden = \"false\" and $dm_doc/dmftversions/iscurrent = \"true\" and $dm_doc/dmftinternal/i_all_types = \"0387db9d800002e9\" and $dm_doc/dmftmetadata//r_object_type = \"tro_claim_document\" and . ftcontains (\"testing\" with stemming using stop words default) order by $s descending return <d>{ $dm_doc/dmftmetadata//r_object_id }{ $dm_doc/dmftmetadata//object_name }{ $dm_doc/dmftmetadata//r_object_type }{ $dm_doc/dmftmetadata//owner_name }{ $dm_doc/dmftmetadata//r_modify_date }</d>";
            xquery.setXQueryString(query);
            IDfXQueryTargets target = clientX.getXQueryTargets(IDfXQueryTargets.DF_FULLTEXT);
            xquery.execute(session, target);
            DfLogger.info(this, "-----XQuery executed successfully-----", null, null);
            InputStream result = xquery.getInputStream(session);
            BufferedReader reader = new BufferedReader(new InputStreamReader(result, "UTF-8"));
            String line;
            while ((line = reader.readLine()) != null) {
                System.out.println(line);
            }
            reader.close();

        } catch (DfException e) {

            DfLogger.error(this, "---Error While executing XPlore XQuery---", null, e);
            throw e;
        } catch (Exception e) {

            DfLogger.error(this, "----Error reading XQuery result----", null, e);
            throw new DfException("There is some issue with the Query" + e.getMessage());

        } finally {
            try {
                xquery.close(session);
            } catch (Exception e) {
                DfLogger.error(this, "-----Error closing XQuery---", null, e);
            }
        }
    }
}