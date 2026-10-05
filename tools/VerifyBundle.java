// Read every payload entry to trigger JAR signature verification, including hashes.
import java.nio.file.Path;
import java.security.MessageDigest;
import java.util.HexFormat;
import java.util.jar.JarFile;

class VerifyBundle {
    public static void main(String[] args) throws Exception {
        var expected = args[1];
        var count = 0;
        try (var jar = new JarFile(Path.of(args[0]).toFile(), true)) {
            var entries = jar.entries();
            while (entries.hasMoreElements()) {
                var entry = entries.nextElement();
                if (entry.isDirectory()) continue;
                try (var stream = jar.getInputStream(entry)) {
                    stream.transferTo(java.io.OutputStream.nullOutputStream());
                }
                if (entry.getName().startsWith("META-INF/")) continue;
                var signers = entry.getCodeSigners();
                if (signers == null || signers.length != 1)
                    throw new SecurityException("Unsigned or multiply signed AAB entry");
                var certificate = signers[0].getSignerCertPath().getCertificates().get(0);
                var hash = HexFormat.of().formatHex(
                    MessageDigest.getInstance("SHA-256").digest(certificate.getEncoded()));
                if (!hash.equals(expected)) throw new SecurityException("Unexpected AAB signer");
                count++;
            }
        }
        if (count == 0) throw new SecurityException("Empty bundle");
        System.out.println("AAB payload signature verified");
    }
}
