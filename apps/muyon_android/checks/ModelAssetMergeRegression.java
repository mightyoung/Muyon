import java.io.File;
import com.android.ide.common.resources.AssetSet;
import com.android.utils.StdLogger;

/** Calls the actual AGP sdk-common AssetSet; no product build or model inference. */
class ModelAssetMergeRegression {
    public static void main(String[] args) throws Exception {
        if (args.length != 2) {
            throw new IllegalArgumentException("Expected main source assets and prepared external assets");
        }
        var assets = new AssetSet("main", null);
        assets.addSource(new File(args[0]));
        assets.addSource(new File(args[1]));
        System.out.println("ASSETSET_LIBRARY=" + AssetSet.class.getProtectionDomain().getCodeSource().getLocation());
        assets.loadFromFiles(new StdLogger(StdLogger.Level.INFO));
        System.out.println("AGP_ASSETSET_MERGE_PASS");
    }
}
