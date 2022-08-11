describe('login a user', () => {
  it('successfully logined', () => {
    cy.visit('http://localhost:4000')
    cy.get('#login-form')
    .find('[type="text"]').type('Cypres test user',{force:true})
    cy.get('#login-form').submit()
  })
  it("check if it's mine login", () => {
    cy.contains("My notes").click()
    cy.get('#chatHeader').find('h1').last().should('have.text', 'Cypres test user')
  })
})
