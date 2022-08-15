describe('login a user', () => {
  const userName = 'Cypres test user';
  const url = Cypress.env('url');
  it('successfully logined', () => {
    cy.visit(url)
    cy.get('.t-form')
    .find('[type="text"]').type(userName,{force:true})
    cy.get('.t-form').submit()
  })
  it("check if it's mine login", () => {
    cy.get('.t-my-notes').click()
    cy.get('.t-chat-header').find('.t-peer-name').should('have.text', userName)
  })
})
