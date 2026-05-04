
!/bin/bash

Navigate into your repo (replace <repo-name> with the actual repo name)
git clone git@github.com:Gitdigital-products/<repo-name>.git
cd <repo-name>

Rename the file
git mv architectcher.md architecture.md

Commit the change
git commit -m "Fix typo: rename architectcher.md to architecture.md"

Push back to GitHub
git push origin main
`

4. Save and exit (CTRL+O, ENTER, CTRL+X in nano).  
5. Make the script executable:
   `bash
   chmod +x nano fix-rename.sh
   `
6. Run it:
   `bash
   ./nano fix-rename.sh
  